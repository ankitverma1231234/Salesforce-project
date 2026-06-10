public with sharing class caseCreationController {
    
    private static String getValidPhone(Account acc) {
    if (String.isNotBlank(acc.PersonHomePhone)) {
        return acc.PersonHomePhone;
    } else if (String.isNotBlank(acc.PersonMobilePhone)) {
        return acc.PersonMobilePhone;
    }
    return '';
}

    @AuraEnabled(cacheable=true)
    public static Account getPersonAccount(Id accountId) {
        system.debug('method started');
        return [
            SELECT Id, Name, PersonEmail, Date_of_Birth__pc, Biological_Sex_at_Birth__c,Maiden_Name__pc,PersonMobilePhone,PersonHomePhone,PersonMailingCity,PersonMailingState,PersonMailingCountry,PersonMailingPostalCode,PersonMailingStreet
            FROM Account
            WHERE Id = :accountId
              AND IsPersonAccount = true
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static Id createCase(
        Id accountId,
        String name,
        String email,
        String dob,
        String city,
        String state,
        String country,
        String zipCode,
        String street,
        String phone,
        String maidanname,
        String biologicalSex,
        String notes,
        String allergyIdsJson,
        String medicationIdsJson,
        String healthConditionIdsJson,
        String healthCareProcedureIdsJson
    ) {
        Date dobDate;
        if (String.isNotBlank(dob)) {
            dobDate = Date.valueOf(dob);
        }

        Case c = new Case(
            AccountId = accountId,
            Origin = 'Web',
            Status = 'New',
            Subject = 'Metriport Case',
            Account_Name__c = name,
            Date_of_Birth__c = dobDate,
            Case_Type__c = 'Metriport Cases'
        );

        insert c;
        
        c = [
    SELECT Id, CreatedDate
    FROM Case
    WHERE Id = :c.Id
];
        System.debug('Case inserted ID: ' + c.Id);

        // Parse the selected IDs
        List<String> allergyIds = parseIds(allergyIdsJson);
        List<String> medicationIds = parseIds(medicationIdsJson);
        List<String> healthConditionIds = parseIds(healthConditionIdsJson);
        List<String> healthCareProcedureIds = parseIds(healthCareProcedureIdsJson);
        // Fetch account to get phone fields
Account acc = [
    SELECT PersonHomePhone, PersonMobilePhone
    FROM Account
    WHERE Id = :accountId
    LIMIT 1
];

// Apply fallback logic
String finalPhone = getValidPhone(acc);

// Override phone
phone = finalPhone;

        // Create and attach JSON file
        createJsonAttachment(
            c.Id,
            accountId,
            allergyIds,
            medicationIds,
            healthConditionIds,
            healthCareProcedureIds,
            name,
            email,
            dob,
            street,
            city,
            state,
            country,
            zipCode,
            phone,
            biologicalSex,
            maidanname,
            notes,
            c.CreatedDate
        );

        return c.Id;
    }

@AuraEnabled
public static Id createCaseAutomated(Id accountId) {
    System.debug('=== createCaseAutomated START === accountId: ' + accountId);

    Account acc = getPersonAccount(accountId);
    System.debug('Account fetched: ' + acc.Name);

    String dobStr = acc.Date_of_Birth__pc != null
        ? DateTime.newInstance(acc.Date_of_Birth__pc, Time.newInstance(0,0,0,0)).format('yyyy-MM-dd')
        : null;

    List<String> allergyIds = new List<String>();
    for (AllergyIntolerance a : getAllergies(accountId)) { allergyIds.add(a.Id); }

    List<String> medicationIds = new List<String>();
    for (MedicationStatement m : getMedications(accountId)) { medicationIds.add(m.Id); }

    List<String> healthConditionIds = new List<String>();
    for (HealthCondition h : getHealthConditions(accountId)) { healthConditionIds.add(h.Id); }

    List<String> procedureIds = new List<String>();
    for (HealthCareProcedure p : getHealthCareProcedures(accountId)) { procedureIds.add(p.Id); }

    System.debug('Child counts -> Allergies: ' + allergyIds.size()
        + ', Medications: ' + medicationIds.size()
        + ', Conditions: ' + healthConditionIds.size()
        + ', Procedures: ' + procedureIds.size());

    Id newCaseId = createCase(
        accountId, acc.Name, acc.PersonEmail, dobStr,
        acc.PersonMailingCity, acc.PersonMailingState, acc.PersonMailingCountry,
        acc.PersonMailingPostalCode, acc.PersonMailingStreet, '',
        acc.Maiden_Name__pc, acc.Biological_Sex_at_Birth__c, '',
        JSON.serialize(allergyIds), JSON.serialize(medicationIds),
        JSON.serialize(healthConditionIds), JSON.serialize(procedureIds)
    );

    System.debug('=== createCaseAutomated END === Case created: ' + newCaseId);
    return newCaseId;
}

    private static List<String> parseIds(String idsJson) {
        if (String.isBlank(idsJson)) {
            return new List<String>();
        }
        return (List<String>) JSON.deserialize(idsJson, List<String>.class);
    }

    private static void createJsonAttachment(
        Id caseId,
        Id accountId,
        List<String> allergyIds,
        List<String> medicationIds,
        List<String> healthConditionIds,
        List<String> healthCareProcedureIds,
        String name,
        String email,
        String dob,
        String street,
        String city,
        String state,
        String country,
        String zipCode,
        String phone,
        String biologicalSex,
        String maidanname,
        String notes,
        Datetime caseCreatedDate
    ) {
        // Build JSON manually to preserve order
        String jsonString = '{\n';
        
        // Add IDs
        jsonString += '  "accountId": "' + accountId + '",\n';
        jsonString += '  "caseId": "' + caseId + '",\n';
        
        // 1. BASIC DETAILS
        jsonString += '  "basic_details": [\n';
        jsonString += '    {\n';
        jsonString += '      "accountId": "' + accountId + '",\n';
        jsonString += '      "name": "' + escapeJson(name) + '",\n';
        jsonString += '      "maidanName": "' + escapeJson(maidanname) + '",\n';
        jsonString += '      "email": "' + escapeJson(email) + '",\n';
        jsonString += '      "phone": "' + escapeJson(phone) + '",\n';
        jsonString += '      "dateOfBirth": "' + (dob != null ? dob : '') + '",\n';
        jsonString += '      "biologicalSexAtBirth": "' + escapeJson(biologicalSex) + '",\n';
        jsonString += '      "mailingAddress": {\n';
        jsonString += '        "street": "' + escapeJson(street) + '",\n';
        jsonString += '        "city": "' + escapeJson(city) + '",\n';
        jsonString += '        "state": "' + escapeJson(state) + '",\n';
        jsonString += '        "country": "' + escapeJson(country) + '",\n';
        jsonString += '        "zipCode": "' + escapeJson(zipCode) + '"\n';
        jsonString += '      },\n';
        jsonString += '      "notes": "' + escapeJson(notes) + '",\n';
        jsonString += '      "caseCreatedDate": "' 
           + caseCreatedDate.format('yyyy-MM-dd HH:mm:ss') 
           + '"\n';

        jsonString += '    }\n';
        jsonString += '  ],\n';
        
        // 2. ALLERGIES
        jsonString += '  "allergies": ' + JSON.serializePretty(getSelectedAllergies(allergyIds)) + ',\n';
        
        // 3. MEDICATIONS
        jsonString += '  "medications": ' + JSON.serializePretty(getSelectedMedications(medicationIds)) + ',\n';
        
        // 4. MEDICAL HISTORY
        jsonString += '  "medical_history": ' + JSON.serializePretty(getSelectedHealthConditions(healthConditionIds)) + ',\n';
        
        // 5. SURGICAL HISTORY
        jsonString += '  "surgical_history": ' + JSON.serializePretty(getSelectedHealthCareProcedures(healthCareProcedureIds)) + '\n';
        
        jsonString += '}';
        
        System.debug('Generated JSON: ' + jsonString);
        String fielname = DateTime.now().format('yyyy-MM-dd') + '  ' + System.Label.Metriport_Case_Name;
      if (!Test.isRunningTest()) {

    System.enqueueJob(
        new GeneratePdfQueueable(
            caseId,
            jsonString,
            fielname
        )
    );
}
        
         //Create ContentVersion (file)
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Case_Medical_Data_' + DateTime.now().format('yyyyMMdd_HHmmss');
        cv.PathOnClient = cv.Title + '.txt';
        cv.VersionData = Blob.valueOf(jsonString);
        cv.FirstPublishLocationId = caseId;
        cv.IsMajorVersion = true;
        
        //insert cv;
        
        //System.debug('JSON file attached to Case: ' + cv.Id);
    }	
   
    
    // Helper method to escape special characters in JSON strings
    private static String escapeJson(String str) {
        if (String.isBlank(str)) {
            return '';
        }
        return str.replace('\\', '\\\\')
                  .replace('"', '\\"')
                  .replace('\n', '\\n')
                  .replace('\r', '\\r')
                  .replace('\t', '\\t');
    }

    private static List<Map<String, Object>> getSelectedAllergies(List<String> allergyIds) {
        if (allergyIds.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        List<AllergyIntolerance> allergies = [
            SELECT Id, Reaction__c, Severity,Note__c,Combine_allergy_and_Generic__c
            FROM AllergyIntolerance
            WHERE Id IN :allergyIds
        ];

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (AllergyIntolerance allergy : allergies) {
            Map<String, Object> allergyMap = new Map<String, Object>();
            allergyMap.put('id', allergy.Id);
            //allergyMap.put('name', allergy.Name);
            allergyMap.put('allergy', allergy.Combine_allergy_and_Generic__c);
            allergyMap.put('severity', allergy.Severity);
            allergyMap.put('reaction', allergy.Reaction__c);
            allergyMap.put('note', allergy.Note__c);
            result.add(allergyMap);
        }
        
        return result;
    }

    private static List<Map<String, Object>> getSelectedMedications(List<String> medicationIds) {
    if (medicationIds.isEmpty()) {
        return new List<Map<String, Object>>();
    }

    List<MedicationStatement> medications = [
        SELECT Id, Medication_Name__c, Dose__c, Frequency__c, Reason__c, Status, CreatedDate
        FROM MedicationStatement
        WHERE Id IN :medicationIds
    ];

    // ✅ SORTING LOGIC (Active first)
    medications.sort(new MedicationSorter());

    List<Map<String, Object>> result = new List<Map<String, Object>>();
    for (MedicationStatement med : medications) {
        Map<String, Object> medMap = new Map<String, Object>();
        medMap.put('id', med.Id);
        medMap.put('name', med.Medication_Name__c);
        medMap.put('dose', med.Dose__c);
        medMap.put('frequency', med.Frequency__c);
        medMap.put('reason', med.Reason__c);
        medMap.put('status', med.Status);
        result.add(medMap);
    }

    return result;
}

   private static List<Map<String, Object>> getSelectedHealthConditions(List<String> healthConditionIds) {
    if (healthConditionIds.isEmpty()) {
        return new List<Map<String, Object>>();
    }

    List<HealthCondition> conditions = [
        SELECT Id, ProblemName, ProblemDescription, ConditionStatus, CreatedDate
        FROM HealthCondition
        WHERE Id IN :healthConditionIds
    ];

    // ✅ SORTING (Active first)
    conditions.sort(new HealthConditionSorter());

    List<Map<String, Object>> result = new List<Map<String, Object>>();
    for (HealthCondition condition : conditions) {
        Map<String, Object> condMap = new Map<String, Object>();
        condMap.put('id', condition.Id);
        condMap.put('name', condition.ProblemName);
        condMap.put('notes', condition.ProblemDescription);
        condMap.put('status', condition.ConditionStatus);
        result.add(condMap);
    }

    return result;
}

    private static List<Map<String, Object>> getSelectedHealthCareProcedures(List<String> procedureIds) {
        if (procedureIds.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        List<HealthCareProcedure> procedures = [
            SELECT Id, Name, Surgery_Name__c, Category,Note__c,EffectiveDate,CreatedDate
            FROM HealthCareProcedure
            WHERE Id IN :procedureIds
            ORDER BY CreatedDate DESC
        ];

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (HealthCareProcedure proc : procedures) {
            Map<String, Object> procMap = new Map<String, Object>();
            procMap.put('id', proc.Id);
            procMap.put('name', proc.Name);
            procMap.put('effective_date', proc.EffectiveDate);
            procMap.put('notes', proc.Note__c);
            //procMap.put('surgeryName', proc.Surgery_Name__c);
            //procMap.put('category', proc.Category);
            result.add(procMap);
        }
        
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<AllergyIntolerance> getAllergies(Id accountId) {
        return [
            SELECT Id, Reaction__c, Severity,Note__c,Combine_allergy_and_Generic__c    
            FROM AllergyIntolerance
            WHERE PatientId = :accountId
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<MedicationStatement> getMedications(Id accountId) {
        return [
            SELECT Id, Medication_Name__c, Dose__c, Frequency__c, Reason__c,Status
            FROM MedicationStatement
            WHERE PatientId = :accountId
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<HealthCondition> getHealthConditions(Id accountId) {
        return [
            SELECT Id, ProblemName, ProblemDescription,ConditionStatus
            FROM HealthCondition
            WHERE PatientId = :accountId
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<HealthCareProcedure> getHealthCareProcedures(Id accountId) {
        try {
            return [
                SELECT Id, Name, Surgery_Name__c, Category,Note__c,EffectiveDate
                FROM HealthCareProcedure 
WHERE Patient__c = :accountId
            ];
        } catch (Exception e) {
            System.debug('Error querying HealthCareProcedure: ' + e.getMessage());
            return new List<HealthCareProcedure>();
        }
    }
}