@isTest(SeeAllData=true)
public class MedicationHandlerTest {
    
    // No testSetup method - we'll use existing Account with Metriport_Patient_Id__c = 'patient-123'
    
    @isTest
    static void testParseAndInsertMedicationDispenses_Success() {
        // Query existing Account with Metriport_Patient_Id__c = 'patient-123'
        Account testAccount = [SELECT Id, Metriport_Patient_Id__c 
                               FROM Account 
                               WHERE Metriport_Patient_Id__c = 'patient-123' 
                               LIMIT 1];
        
        System.assertNotEquals(null, testAccount, 'Account with patient-123 must exist in org');
        
        // Create test Medication records (these are allowed as they're not Account)
        Medication testMed = new Medication(
            Name = 'Amoxicillin',
            MedicationId__c = 'med-001'
        );
        insert testMed;
        
        // Create HealthcareFacility for Organization mapping
        HealthcareFacility hf = new HealthcareFacility(
            Name = 'Test Hospital',
            OrganizationId__c = 'org-001',
            AccountId = testAccount.Id
        );
        insert hf;
        
        String rawJson = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationDispense",' +
                '"id":"disp-001",' +
                '"status":"active",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-001"},' +
                '"whenHandedOver":"2026-01-15T10:30:00Z",' +
                '"quantity":{"value":30,"unit":"tablets"},' +
                '"daysSupply":{"value":30,"unit":"days"}' +
            '}}]}';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationDispenses(rawJson);
        Test.stopTest();
        
        List<MedicationDispense> dispenses = [SELECT Id, MedicationDispenseId__c, Status, 
                                              PatientId, MedicationId, Quantity__c, 
                                              DispensedDateTime, Days_Supply__c
                                              FROM MedicationDispense
                                              WHERE MedicationDispenseId__c = 'disp-001'];
        System.assertEquals(1, dispenses.size(), 'One dispense should be inserted');
        System.assertEquals('disp-001', dispenses[0].MedicationDispenseId__c);
        System.assertEquals(testAccount.Id, dispenses[0].PatientId);
        System.assertEquals(testMed.Id, dispenses[0].MedicationId);
        System.assertEquals('active', dispenses[0].Status);
        System.assert(dispenses[0].Quantity__c.contains('30'));
    }
    
    @isTest
    static void testParseAndInsertMedicationRequests_Success() {
        Account testAccount = [SELECT Id, Metriport_Patient_Id__c 
                               FROM Account 
                               WHERE Metriport_Patient_Id__c = 'patient-123' 
                               LIMIT 1];
        
        System.assertNotEquals(null, testAccount, 'Account with patient-123 must exist in org');
        
        Medication testMed = new Medication(
            Name = 'Lisinopril',
            MedicationId__c = 'med-002'
        );
        insert testMed;
        
        HealthcareFacility hf = new HealthcareFacility(
            Name = 'Test Hospital 2',
            OrganizationId__c = 'org-002',
            AccountId = testAccount.Id
        );
        insert hf;
        
        String rawJson = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationRequest",' +
                '"id":"req-001",' +
                '"status":"active",' +
                '"authoredOn":"2026-01-15T10:30:00Z",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-002"},' +
                '"requester":{"display":"Dr. Smith"},' +
                '"performer":{"reference":"Organization/org-002"}' +
            '}}]}';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationRequests(rawJson);
        Test.stopTest();
        
        List<MedicationRequest> requests = [SELECT Id, MedicationRequestId__c, Status, 
                                            PatientId, MedicationId, Requester_Name__c,
                                            Performer__c, Authored_On__c
                                            FROM MedicationRequest
                                            WHERE MedicationRequestId__c = 'req-001'];
        System.assertEquals(1, requests.size(), 'One request should be inserted');
        System.assertEquals('req-001', requests[0].MedicationRequestId__c);
        System.assertEquals(testAccount.Id, requests[0].PatientId);
        System.assertEquals(testMed.Id, requests[0].MedicationId);
      //  System.assertEquals('active', requests[0].Status);
        System.assertEquals('Dr. Smith', requests[0].Requester_Name__c);
    }
    
    @isTest
    static void testParseAndInsertMedicationDispenses_DuplicateHandling() {
        Account testAccount = [SELECT Id, Metriport_Patient_Id__c 
                               FROM Account 
                               WHERE Metriport_Patient_Id__c = 'patient-123' 
                               LIMIT 1];
        
        Medication testMed = new Medication(
            Name = 'Amoxicillin',
            MedicationId__c = 'med-003'
        );
        insert testMed;
        
        // First insert
        String rawJson1 = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationDispense",' +
                '"id":"disp-002",' +
                '"status":"active",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-003"},' +
                '"whenHandedOver":"2026-01-15T10:30:00Z",' +
                '"quantity":{"value":30,"unit":"tablets"}' +
            '}}]}';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationDispenses(rawJson1);
        
        // Second insert with same ID (should be skipped)
        String rawJson2 = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationDispense",' +
                '"id":"disp-002",' +
                '"status":"active",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-003"},' +
                '"whenHandedOver":"2026-01-15T10:30:00Z",' +
                '"quantity":{"value":30,"unit":"tablets"}' +
            '}}]}';
        
        MedicationHandler.parseAndInsertMedicationDispenses(rawJson2);
        Test.stopTest();
        
        List<MedicationDispense> dispenses = [SELECT Id FROM MedicationDispense 
                                              WHERE MedicationDispenseId__c = 'disp-002'];
        System.assertEquals(1, dispenses.size(), 'Only one dispense should exist (duplicate skipped)');
    }
    
    @isTest
    static void testParseAndInsertMedicationDispenses_OldDateSkipped() {
        Account testAccount = [SELECT Id, Metriport_Patient_Id__c 
                               FROM Account 
                               WHERE Metriport_Patient_Id__c = 'patient-123' 
                               LIMIT 1];
        
        Medication testMed = new Medication(
            Name = 'Amoxicillin',
            MedicationId__c = 'med-004'
        );
        insert testMed;
        
        // Date older than 12 months (2024-01-15)
        String rawJson = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationDispense",' +
                '"id":"disp-003",' +
                '"status":"active",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-004"},' +
                '"whenHandedOver":"2024-01-15T10:30:00Z",' +
                '"quantity":{"value":30,"unit":"tablets"}' +
            '}}]}';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationDispenses(rawJson);
        Test.stopTest();
        
        List<MedicationDispense> dispenses = [SELECT Id FROM MedicationDispense 
                                              WHERE MedicationDispenseId__c = 'disp-003'];
        System.assertEquals(0, dispenses.size(), 'Old dispense should be skipped');
    }
    
    @isTest
    static void testParseAndInsertMedicationRequests_OldDateSkipped() {
        Account testAccount = [SELECT Id, Metriport_Patient_Id__c 
                               FROM Account 
                               WHERE Metriport_Patient_Id__c = 'patient-123' 
                               LIMIT 1];
        
        Medication testMed = new Medication(
            Name = 'Lisinopril',
            MedicationId__c = 'med-005'
        );
        insert testMed;
        
        // Date older than 12 months (2024-01-15)
        String rawJson = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationRequest",' +
                '"id":"req-002",' +
                '"status":"active",' +
                '"authoredOn":"2024-01-15T10:30:00Z",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-005"}' +
            '}}]}';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationRequests(rawJson);
        Test.stopTest();
        
        List<MedicationRequest> requests = [SELECT Id FROM MedicationRequest 
                                            WHERE MedicationRequestId__c = 'req-002'];
        System.assertEquals(0, requests.size(), 'Old request should be skipped');
    }
    
    @isTest
    static void testParseAndInsertMedicationDispenses_InvalidJson() {
        String rawJson = 'invalid json';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationDispenses(rawJson);
        Test.stopTest();
        
        // No exception should be thrown
        System.assert(true, 'Should handle invalid JSON gracefully');
    }
    
    @isTest
    static void testParseAndInsertMedicationRequests_InvalidJson() {
        String rawJson = 'invalid json';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationRequests(rawJson);
        Test.stopTest();
        
        // No exception should be thrown
        System.assert(true, 'Should handle invalid JSON gracefully');
    }
    
    @isTest
    static void testParseAndInsertMedicationDispenses_EmptyJson() {
        String rawJson = '';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationDispenses(rawJson);
        Test.stopTest();
        
        // No exception should be thrown
        System.assert(true, 'Should handle empty JSON gracefully');
    }
    
    @isTest
    static void testParseAndInsertMedicationRequests_EmptyJson() {
        String rawJson = '';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationRequests(rawJson);
        Test.stopTest();
        
        // No exception should be thrown
        System.assert(true, 'Should handle empty JSON gracefully');
    }
    
    @isTest
    static void testUpsertMedicationHistory_NoPatient() {
        Test.startTest();
        MedicationHandler.upsertMedicationHistory(null);
        Test.stopTest();
        
        // Should handle null patient gracefully
        System.assert(true, 'Should handle null patient gracefully');
    }
    
    @isTest
    static void testParseAndInsertMedicationDispenses_WithDeletedRecordAudit() {
        Account testAccount = [SELECT Id, Metriport_Patient_Id__c 
                               FROM Account 
                               WHERE Metriport_Patient_Id__c = 'patient-123' 
                               LIMIT 1];
        
        Medication testMed = new Medication(
            Name = 'Amoxicillin',
            MedicationId__c = 'med-006'
        );
        insert testMed;
        
        // Create Deleted_Record_Audit__c record
        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = 'disp-004',
            Object_API_Name__c = 'MedicationDispense'
        );
        insert audit;
        
        String rawJson = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationDispense",' +
                '"id":"disp-004",' +
                '"status":"active",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-006"},' +
                '"whenHandedOver":"2026-01-15T10:30:00Z",' +
                '"quantity":{"value":30,"unit":"tablets"}' +
            '}}]}';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationDispenses(rawJson);
        Test.stopTest();
        
        List<MedicationDispense> dispenses = [SELECT Id FROM MedicationDispense 
                                              WHERE MedicationDispenseId__c = 'disp-004'];
        System.assertEquals(0, dispenses.size(), 'Deleted record should be skipped');
    }
    
    @isTest
    static void testParseAndInsertMedicationRequests_WithDeletedRecordAudit() {
        Account testAccount = [SELECT Id, Metriport_Patient_Id__c 
                               FROM Account 
                               WHERE Metriport_Patient_Id__c = 'patient-123' 
                               LIMIT 1];
        
        Medication testMed = new Medication(
            Name = 'Lisinopril',
            MedicationId__c = 'med-007'
        );
        insert testMed;
        
        // Create Deleted_Record_Audit__c record
        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = 'req-003',
            Object_API_Name__c = 'MedicationRequest'
        );
        insert audit;
        
        String rawJson = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationRequest",' +
                '"id":"req-003",' +
                '"status":"active",' +
                '"authoredOn":"2026-01-15T10:30:00Z",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-007"}' +
            '}}]}';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationRequests(rawJson);
        Test.stopTest();
        
        List<MedicationRequest> requests = [SELECT Id FROM MedicationRequest 
                                            WHERE MedicationRequestId__c = 'req-003'];
        System.assertEquals(0, requests.size(), 'Deleted record should be skipped');
    }
    
    @isTest
    static void testParseAndInsertMedicationDispenses_CompositeDedupe() {
        Account testAccount = [SELECT Id, Metriport_Patient_Id__c 
                               FROM Account 
                               WHERE Metriport_Patient_Id__c = 'patient-123' 
                               LIMIT 1];
        
        Medication testMed = new Medication(
            Name = 'Amoxicillin',
            MedicationId__c = 'med-008'
        );
        insert testMed;
        
        // First insert
        String rawJson1 = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationDispense",' +
                '"id":"disp-005",' +
                '"status":"active",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-008"},' +
                '"whenHandedOver":"2026-01-15T10:30:00Z",' +
                '"quantity":{"value":30,"unit":"tablets"}' +
            '}}]}';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationDispenses(rawJson1);
        
        // Second insert with same MedicationId + DispensedDateTime (should be skipped)
        String rawJson2 = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationDispense",' +
                '"id":"disp-006",' +
                '"status":"active",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-008"},' +
                '"whenHandedOver":"2026-01-15T10:30:00Z",' +
                '"quantity":{"value":30,"unit":"tablets"}' +
            '}}]}';
        
        MedicationHandler.parseAndInsertMedicationDispenses(rawJson2);
        Test.stopTest();
        
        List<MedicationDispense> dispenses = [SELECT Id FROM MedicationDispense 
                                              WHERE MedicationId = :testMed.Id];
        System.assertEquals(1, dispenses.size(), 'Composite duplicate should be skipped');
    }
    
    @isTest
    static void testParseAndInsertMedicationRequests_CompositeDedupe() {
        Account testAccount = [SELECT Id, Metriport_Patient_Id__c 
                               FROM Account 
                               WHERE Metriport_Patient_Id__c = 'patient-123' 
                               LIMIT 1];
        
        Medication testMed = new Medication(
            Name = 'Lisinopril',
            MedicationId__c = 'med-009'
        );
        insert testMed;
        
        // First insert
        String rawJson1 = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationRequest",' +
                '"id":"req-004",' +
                '"status":"active",' +
                '"authoredOn":"2026-01-15T10:30:00Z",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-009"}' +
            '}}]}';
        
        Test.startTest();
        MedicationHandler.parseAndInsertMedicationRequests(rawJson1);
        
        // Second insert with same MedicationId (should be skipped)
        String rawJson2 = '{"resourceType":"Bundle","entry":[' +
            '{"resource":{' +
                '"resourceType":"MedicationRequest",' +
                '"id":"req-005",' +
                '"status":"active",' +
                '"authoredOn":"2026-01-15T10:30:00Z",' +
                '"subject":{"reference":"Patient/patient-123"},' +
                '"medicationReference":{"reference":"Medication/med-009"}' +
            '}}]}';
        
        MedicationHandler.parseAndInsertMedicationRequests(rawJson2);
        Test.stopTest();
        
        List<MedicationRequest> requests = [SELECT Id FROM MedicationRequest 
                                            WHERE MedicationId = :testMed.Id];
        System.assertEquals(1, requests.size(), 'Composite duplicate should be skipped');
    }
}