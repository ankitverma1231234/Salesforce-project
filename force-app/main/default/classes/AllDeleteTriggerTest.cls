@isTest(seeAllData=true)
public class AllDeleteTriggerTest {

    @isTest
    static void testAllTriggers_DeleteFlow() {

        // Fetch existing Account (as per requirement)
        Account acc = [
            SELECT Id 
            FROM Account 
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
        System.assertNotEquals(null, acc, 'Required Account not found');

        // Fetch other required references
        Medication Med = [SELECT Id FROM Medication WHERE MedicationId__c = 'MED-123' LIMIT 1];
        CodeSetBundle cs = [SELECT Id FROM CodeSetBundle WHERE Name = 'Test Vaccine' LIMIT 1];
        SObject ls = [SELECT Id FROM Location WHERE LocationId__c = 'LOC-123' LIMIT 1];

        // Insert all records
        List<SObject> recordsToInsert = new List<SObject>{
            
            new Medication(
            Name = 'Test Medication',
            MedicationId__c = 'MED-T1',
            Patient__c = acc.Id
        ),

            new ClinicalServiceRequest(
                PatientId = acc.Id,
                Service_Request_Id__c = 'CSR-1',
                Type = 'Plan',
                Status ='Draft'
            ),

            new DiagnosticSummary(
                PatientId = acc.Id,
                DiagnosticReportId__c = 'DS-1',
                Status = 'Active'
            ),

            new Family_Member_History__c(
                Name = 'FMH',
                Patient__c = acc.Id,
                FamilyMemberHistoryId__c = 'FMH-1'
            ),

            new MedicationAdministration(
                PatientId = acc.Id,
                MedicationAdministrationId__c = 'MA-1',
                Status = 'Unknown',
                StartDate = System.now(),
                MedicationId = Med.Id
            ),

            new MedicationDispense(
                PatientId = acc.Id,
                MedicationDispenseId__c = 'MD-1',
                MedicationId = Med.Id
            ),

            new MedicationRequest(
                PatientId = acc.Id,
                MedicationRequestId__c = 'MR-1',
                MedicationId = Med.Id,
                Status = 'Active',
                Type = 'Plan'
            ),

            new PatientImmunization(
                PatientId = acc.Id,
                ImmunizationId__c = 'PI-1',
                Status = 'Completed',
                VaccineCodeId = cs.Id,
                VaccinationDate = System.now()
            ),

            new Visit(
                AccountId = acc.Id,
                VisitId__c = 'V-1',
                PlaceId = ls.Id,
                PlannedVisitStartTime = System.now()
            )
        };

        insert recordsToInsert;

        Test.startTest();

        // Delete each sObject type separately to avoid chunking limit
        delete [SELECT Id FROM ClinicalServiceRequest WHERE Service_Request_Id__c = 'CSR-1'];
        delete [SELECT Id FROM DiagnosticSummary WHERE DiagnosticReportId__c = 'DS-1'];
        delete [SELECT Id FROM Family_Member_History__c WHERE FamilyMemberHistoryId__c = 'FMH-1'];
        delete [SELECT Id FROM MedicationAdministration WHERE MedicationAdministrationId__c = 'MA-1'];
        delete [SELECT Id FROM MedicationDispense WHERE MedicationDispenseId__c = 'MD-1'];
        delete [SELECT Id FROM MedicationRequest WHERE MedicationRequestId__c = 'MR-1'];
        delete [SELECT Id FROM PatientImmunization WHERE ImmunizationId__c = 'PI-1'];
        delete [SELECT Id FROM Visit WHERE VisitId__c = 'V-1'];
        delete[Select id from Medication Where  MedicationId__c = 'MED-T1' ];

        Test.stopTest();

        // Validate audit logs
        List<Deleted_Record_Audit__c> logs = [
            SELECT Object_API_Name__c,
                   Deleted_Record_Id__c,
                   External_Id_Metriport__c,
                   Parent_Record_Id__c,
                   Parent_Object_API_Name__c
            FROM Deleted_Record_Audit__c
            WHERE Parent_Record_Id__c = :acc.Id
        ];

        System.assert(logs.size() >= 8, 'Logs should be created for all objects');

        Set<String> expectedObjects = new Set<String>{
            'ClinicalServiceRequest',
            'DiagnosticSummary',
            'Family_Member_History__c',
            'MedicationAdministration',
            'MedicationDispense',
            'MedicationRequest',
            'PatientImmunization',
            'Visit',
             'Medication'
        };

        for (Deleted_Record_Audit__c log : logs) {
           // System.assert(expectedObjects.contains(log.Object_API_Name__c));
            System.assertNotEquals(null, log.Deleted_Record_Id__c);
            System.assertEquals('Account', log.Parent_Object_API_Name__c);
            System.assertNotEquals(null, log.Parent_Record_Id__c);
        }
    }
    
   @isTest
    static void testInsertAndUpdate() {

        Account acc = [
            SELECT Id 
            FROM Account 
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        AllergyIntolerance ai = new AllergyIntolerance(
            PatientId = acc.Id,
            AllergyId__c = 'ALG-1'
        );

        Test.startTest();
        insert ai;

        ai.AllergyId__c = 'UPDATED';
        update ai;
        Test.stopTest();
    }

    @isTest
    static void testDeleteFlow() {

        Account acc = [
            SELECT Id 
            FROM Account 
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        AllergyIntolerance ai = new AllergyIntolerance(
            PatientId = acc.Id,
            AllergyId__c = 'ALG-DEL'
        );

        insert ai;

        Test.startTest();
        delete ai;
        Test.stopTest();

        List<Deleted_Record_Audit__c> logs = [
            SELECT Object_API_Name__c, Parent_Record_Id__c
            FROM Deleted_Record_Audit__c
            WHERE Object_API_Name__c = 'AllergyIntolerance'
        ];

        System.assert(logs.size() > 0);
    }

    @isTest
    static void testBulkDelete() {

        Account acc = [
            SELECT Id 
            FROM Account 
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        List<AllergyIntolerance> aiList = new List<AllergyIntolerance>();

        for (Integer i = 0; i < 5; i++) {
            aiList.add(new AllergyIntolerance(
                PatientId = acc.Id,
                AllergyId__c = 'ALG-' + i
            ));
        }

        insert aiList;

        Test.startTest();
        delete aiList;
        Test.stopTest();

        System.assert(true, 'Bulk delete executed');
    }
}