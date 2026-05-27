public with sharing class AllergyPdfController {
    /*

    public Id caseId { get; set; }
    public Case caseRec { get; set; }
    public Account accountRec { get; set; }
    public List<AllergyIntolerance> allergies { get; set; }
    public List<MedicationStatement> medications { get; set; }
    public List<HealthCondition> healthConditions { get; set; }
    public List<HealthCareProcedure> healthCareProcedures { get; set; }
    
    public String allergyIdsJson { get; set; }
    public String medicationIdsJson { get; set; }
    public String healthConditionIdsJson { get; set; }
    public String healthCareProcedureIdsJson { get; set; }
    public String editedDataJson { get; set; }
    
    public Set<Id> selectedAllergyIds { get; set; }
    public Set<Id> selectedMedicationIds { get; set; }
    public Set<Id> selectedHealthConditionIds { get; set; }
    public Set<Id> selectedHealthCareProcedureIds { get; set; }
    public Map<String, Object> editedDataMap { get; set; }

    public AllergyPdfController() {

        caseId = ApexPages.currentPage().getParameters().get('caseId');

        // Retrieve payload from Case_PDF_Data__c
        Case_PDF_Data__c pdfData = [
            SELECT Payload_JSON__c
            FROM Case_PDF_Data__c
            WHERE Case__c = :caseId
            LIMIT 1
        ];

        if (pdfData != null && String.isNotBlank(pdfData.Payload_JSON__c)) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(pdfData.Payload_JSON__c);
            allergyIdsJson = (String) payload.get('allergyIds');
            medicationIdsJson = (String) payload.get('medicationIds');
            healthConditionIdsJson = (String) payload.get('healthConditionIds');
            healthCareProcedureIdsJson = (String) payload.get('healthCareProcedureIds');
            editedDataJson = (String) payload.get('editedData');
        }

        caseRec = [
            SELECT Id, CaseNumber, AccountId
            FROM Case
            WHERE Id = :caseId
        ];

        accountRec = [
            SELECT Id, Name
            FROM Account
            WHERE Id = :caseRec.AccountId
        ];

        // Initialize lists
        allergies = new List<AllergyIntolerance>();
        medications = new List<MedicationStatement>();
        healthConditions = new List<HealthCondition>();
        healthCareProcedures = new List<HealthCareProcedure>();

        // Parse selected IDs for each type
        selectedAllergyIds = parseIds(allergyIdsJson);
        selectedMedicationIds = parseIds(medicationIdsJson);
        selectedHealthConditionIds = parseIds(healthConditionIdsJson);
        selectedHealthCareProcedureIds = parseIds(healthCareProcedureIdsJson);

        // Query Allergies
        if (!selectedAllergyIds.isEmpty()) {
            allergies = [
                SELECT Id, Name, Generic__c, Reaction__c, Allergy_Name__c,Severity
                FROM AllergyIntolerance
                WHERE Id IN :selectedAllergyIds
                ORDER BY CreatedDate
            ];
        }

        // Query Medications
        if (!selectedMedicationIds.isEmpty()) {
            medications = [
                SELECT Id, Name, Dose__c, Frequency__c, Reason__c
                FROM MedicationStatement
                WHERE Id IN :selectedMedicationIds
                ORDER BY CreatedDate
            ];
        }

        // Query Health Conditions
        if (!selectedHealthConditionIds.isEmpty()) {
            healthConditions = [
                SELECT Id, Name, ProblemName, ProblemDescription
                FROM HealthCondition
                WHERE Id IN :selectedHealthConditionIds
                ORDER BY CreatedDate
            ];
        }

        // Query Health Care Procedures
        if (!selectedHealthCareProcedureIds.isEmpty()) {
            healthCareProcedures = [
                SELECT Id, Name, Surgery_Name__c
                FROM HealthCareProcedure
                WHERE Id IN :selectedHealthCareProcedureIds
                ORDER BY CreatedDate
            ];
        }

        // Parse and apply edited data if available
        if (String.isNotBlank(editedDataJson)) {
            try {
                editedDataMap = (Map<String, Object>) JSON.deserializeUntyped(editedDataJson);
                applyEditedData();
            } catch (Exception e) {
                System.debug('Error parsing edited data: ' + e.getMessage());
            }
        }
    }

    private Set<Id> parseIds(String idsJson) {
        Set<Id> ids = new Set<Id>();
        if (String.isNotBlank(idsJson)) {
            try {
                List<String> idList = (List<String>) JSON.deserialize(idsJson, List<String>.class);
                for (String id : idList) {
                    ids.add((Id)id);
                }
            } catch (Exception e) {
                System.debug('Error parsing IDs: ' + e.getMessage());
            }
        }
        return ids;
    }

    private void applyEditedData() {
        if (editedDataMap == null || editedDataMap.isEmpty()) return;

        // Apply edits to allergies
        for (AllergyIntolerance allergy : allergies) {
            String allergyId = allergy.Id;
            if (editedDataMap.containsKey(allergyId)) {
                Map<String, Object> editedRecord = (Map<String, Object>) editedDataMap.get(allergyId);
                
                if (editedRecord.containsKey('Allergy_Name__c')) {
                    allergy.Allergy_Name__c = (String) editedRecord.get('Allergy_Name__c');
                }
                if (editedRecord.containsKey('Generic__c')) {
                    allergy.Generic__c = (String) editedRecord.get('Generic__c');
                }
                if (editedRecord.containsKey('Severity')) {
                    allergy.Severity = (String) editedRecord.get('Severity');
                }
            }
        }

        // Apply edits to medications
        for (MedicationStatement med : medications) {
            String medId = med.Id;
            if (editedDataMap.containsKey(medId)) {
                Map<String, Object> editedRecord = (Map<String, Object>) editedDataMap.get(medId);
                
                if (editedRecord.containsKey('Dose__c')) {
                    med.Dose__c = (String) editedRecord.get('Dose__c');
                }
                if (editedRecord.containsKey('Frequency__c')) {
                    med.Frequency__c = (String) editedRecord.get('Frequency__c');
                }
                if (editedRecord.containsKey('Reason__c')) {
                    med.Reason__c = (String) editedRecord.get('Reason__c');
                }
            }
        }

        // Apply edits to health conditions
        for (HealthCondition hc : healthConditions) {
            String hcId = hc.Id;
            if (editedDataMap.containsKey(hcId)) {
                Map<String, Object> editedRecord = (Map<String, Object>) editedDataMap.get(hcId);
                
                if (editedRecord.containsKey('ProblemName')) {
                    hc.ProblemName = (String) editedRecord.get('ProblemName');
                }
                if (editedRecord.containsKey('ProblemDescription')) {
                    hc.ProblemDescription = (String) editedRecord.get('ProblemDescription');
                }
            }
        }

        // Apply edits to health care procedures
        for (HealthCareProcedure hcp : healthCareProcedures) {
            String hcpId = hcp.Id;
            if (editedDataMap.containsKey(hcpId)) {
                Map<String, Object> editedRecord = (Map<String, Object>) editedDataMap.get(hcpId);
                
                if (editedRecord.containsKey('Surgery_Name__c')) {
                    hcp.Surgery_Name__c = (String) editedRecord.get('Surgery_Name__c');
                }
                
            }
        }
    }
*/
}