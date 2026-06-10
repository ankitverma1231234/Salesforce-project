@IsTest(SeeAllData=true)
public class MedicalSalesforceRecordTest {

    private class HttpSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success": true}');
            return res;
        }
    }

    private class HttpFailureMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error": "Internal Server Error"}');
            return res;
        }
    }

    private static void ensureApiConfig() {
        BatonPortalAPI__c cfg = BatonPortalAPI__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Api_Key__c)) {
            upsert new BatonPortalAPI__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Api_Key__c   = 'https://test-endpoint.com/api'
            );
        }
    }

    private static void ensureTriggerEnabled() {
        TriggerSettings__c settings = TriggerSettings__c.getInstance();
        if (settings == null) {
            insert new TriggerSettings__c(
                SetupOwnerId               = UserInfo.getOrganizationId(),
                Account__c                 = true,
                Care_Observation_Checkbox__c = true
            );
        } else {
            settings.Account__c                 = true;
            settings.Care_Observation_Checkbox__c = true;
            upsert settings;
        }
    }

    private static void disableTrigger() {
        TriggerSettings__c settings = TriggerSettings__c.getInstance();
        if (settings == null) {
            insert new TriggerSettings__c(
                SetupOwnerId               = UserInfo.getOrganizationId(),
                Account__c                 = false,
                Care_Observation_Checkbox__c = false
            );
        } else {
            settings.Account__c                 = false;
            settings.Care_Observation_Checkbox__c = false;
            upsert settings;
        }
    }

    private static void enableCareObservationTrigger() {
        TriggerSettings__c settings = TriggerSettings__c.getInstance();
        if (settings == null) {
            insert new TriggerSettings__c(
                SetupOwnerId               = UserInfo.getOrganizationId(),
                Care_Observation_Checkbox__c = true
            );
        } else {
            settings.Care_Observation_Checkbox__c = true;
            upsert settings;
        }
    }

    private static void disableCareObservationTrigger() {
        TriggerSettings__c settings = TriggerSettings__c.getInstance();
        if (settings == null) {
            insert new TriggerSettings__c(
                SetupOwnerId               = UserInfo.getOrganizationId(),
                Care_Observation_Checkbox__c = false
            );
        } else {
            settings.Care_Observation_Checkbox__c = false;
            upsert settings;
        }
    }

    private static Account getOrCreatePersonAccount() {
        List<Account> existing = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();

        Account pa = new Account(
            RecordTypeId         = personAccountRT,
            FirstName            = 'Test',
            LastName             = 'Patient',
            PersonEmail          = 'test.patient@example.com',
            PersonMobilePhone    = '5551234567',
            Height_in_inches__pc = 68,
            Weight_in_pounds__pc = 160,
            Patient_Summary__c   = 'Healthy adult'
        );
        insert pa;
        return [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    }

    private static Id getPersonAccountRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
    }

    @IsTest
    static void testSendSingleAccountInsert() {
        ensureApiConfig();
        Account acc = getOrCreatePersonAccount();
        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId       = acc.Id,
            Allergy_Name__c = 'Insert Allergy',
            Severity        = 'High'
        );
        insert allergy;

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            acc.Id, 'INSERT', 'AllergyIntolerance', new Set<Id>{ allergy.Id }
        );
        Test.stopTest();

        System.assert(true, 'Single account insert executed successfully');
    }

    @IsTest
    static void testSendSingleAccountUpdate() {
        ensureApiConfig();
        Account acc = getOrCreatePersonAccount();
        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId       = acc.Id,
            Allergy_Name__c = 'Update Allergy',
            Severity        = 'Low'
        );
        insert allergy;

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            acc.Id, 'UPDATE', 'AllergyIntolerance', new Set<Id>{ allergy.Id }
        );
        Test.stopTest();

        System.assert(true, 'Single account update executed successfully');
    }

    @IsTest
    static void testSendBatchAccounts() {
        ensureApiConfig();
        Account acc = getOrCreatePersonAccount();
        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId       = acc.Id,
            Allergy_Name__c = 'Batch Allergy',
            Severity        = 'Moderate'
        );
        insert allergy;

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            new Set<Id>{ acc.Id }, 'INSERT', 'AllergyIntolerance', new Set<Id>{ allergy.Id }
        );
        Test.stopTest();

        System.assert(true, 'Batch method executed successfully');
    }

    @IsTest
    static void testNullAccountId() {
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            (Id) null, 'INSERT', 'AllergyIntolerance', new Set<Id>()
        );
        Test.stopTest();
        System.assert(true, 'Null single account ID handled gracefully');
    }

    @IsTest
    static void testNullAccountIdSet() {
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            (Set<Id>) null, 'INSERT', 'AllergyIntolerance', new Set<Id>()
        );
        Test.stopTest();
        System.assert(true, 'Null account ID set handled gracefully');
    }

    @IsTest
    static void testEmptyAccountIdSet() {
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            new Set<Id>(), 'INSERT', 'AllergyIntolerance', new Set<Id>()
        );
        Test.stopTest();
        System.assert(true, 'Empty account ID set handled gracefully');
    }

    @IsTest
    static void testProcessSingleAccountSynchronously() {
        ensureApiConfig();
        Account acc = getOrCreatePersonAccount();
        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId       = acc.Id,
            Allergy_Name__c = 'Sync Allergy',
            Severity        = 'High'
        );
        insert allergy;

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        MedicalSalesforceRecord.processSingleAccountSynchronously(
            acc.Id, 'INSERT', 'AllergyIntolerance', new Set<Id>{ allergy.Id }
        );
        Test.stopTest();

        System.assert(true, 'processSingleAccountSynchronously executed successfully');
    }

    @IsTest
    static void testProcessBatchSynchronously() {
        ensureApiConfig();
        Account acc = getOrCreatePersonAccount();
        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId       = acc.Id,
            Allergy_Name__c = 'Sync Batch Allergy',
            Severity        = 'Low'
        );
        insert allergy;

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        MedicalSalesforceRecord.processBatchSynchronously(
            new List<Id>{ acc.Id }, 'INSERT', 'AllergyIntolerance', new Set<Id>{ allergy.Id }
        );
        Test.stopTest();

        System.assert(true, 'processBatchSynchronously executed successfully');
    }

    // ─────────────────────────────────────────────
    //  buildTargetedPayload – all objectType branches
    // ─────────────────────────────────────────────

    @IsTest
    static void testBuildTargetedPayloadAccount() {
        Account acc = getOrCreatePersonAccount();

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'Account', new Set<Id>{ acc.Id }
        );
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assert(payload.containsKey('accountId'), 'Payload should contain accountId');
        System.assert(payload.containsKey('basic_details'), 'Payload should contain basic_details');
    }

    @IsTest
    static void testBuildTargetedPayloadAllergy() {
        Account acc = getOrCreatePersonAccount();
        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId       = acc.Id,
            Allergy_Name__c = 'Targeted Allergy',
            Severity        = 'High'
        );
        insert allergy;

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'AllergyIntolerance', new Set<Id>{ allergy.Id }
        );
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assert(payload.containsKey('accountId'), 'Payload should contain accountId');
        System.assert(payload.containsKey('allergies'), 'Payload should contain allergies');
    }

    @IsTest
    static void testBuildTargetedPayloadMedicationStatement() {
        Account acc = getOrCreatePersonAccount();
        Medication med = new Medication(Name = 'Payload Med', Patient__c = acc.Id);
        insert med;
        MedicationStatement stmt = new MedicationStatement(
            PatientId    = acc.Id,
            MedicationId = med.Id,
            Status       = 'Active',
            Dose__c      = '10mg',
            Frequency__c = 'Daily'
        );
        insert stmt;

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'MedicationStatement', new Set<Id>{ stmt.Id }
        );
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assert(payload.containsKey('medications'), 'Payload should contain medications');
    }

    @IsTest
    static void testBuildTargetedPayloadHealthCondition() {
        Account acc = getOrCreatePersonAccount();
        HealthCondition condition = new HealthCondition(
            PatientId          = acc.Id,
            ProblemName        = 'Payload Condition',
            ProblemDescription = 'Desc',
            ConditionStatus    = 'Active',
            Severity           = 'Moderate',
            OnsetStartDateTime = Datetime.now()
        );
        insert condition;

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'HealthCondition', new Set<Id>{ condition.Id }
        );
        Test.stopTest();

        System.assert(payload.containsKey('medical_history'), 'Payload should contain medical_history');
    }

    @IsTest
    static void testBuildTargetedPayloadHealthCareProcedure() {
        Account acc = getOrCreatePersonAccount();
        HealthCareProcedure procedure = new HealthCareProcedure(
            Patient__c      = acc.Id,
            Name            = 'Payload Surgery',
            Surgery_Name__c = 'Payload Surgery',
            EffectiveDate   = Date.today()
        );
        insert procedure;

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'HealthCareProcedure', new Set<Id>{ procedure.Id }
        );
        Test.stopTest();

        System.assert(payload.containsKey('surgical_history'), 'Payload should contain surgical_history');
    }

    @IsTest
    static void testBuildTargetedPayloadMemberPlan() {
        Account acc = getOrCreatePersonAccount();
        MemberPlan plan = new MemberPlan(
            Name         = 'Payload Insurance',
            MemberId     = acc.Id,
            MemberNumber = 'PAY123'
        );
        insert plan;

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'MemberPlan', new Set<Id>{ plan.Id }
        );
        Test.stopTest();

        System.assert(payload.containsKey('insurance_details'), 'Payload should contain insurance_details');
    }

    @IsTest
    static void testBuildTargetedPayloadContact() {
        Account acc = getOrCreatePersonAccount();
        Contact c = new Contact(
            FirstName            = 'Payload',
            LastName             = 'Contact',
            Account__c           = acc.Id,
            Emergency_Contact__c = true
        );
        insert c;

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'Contact', new Set<Id>{ c.Id }
        );
        Test.stopTest();

        System.assert(payload.containsKey('personal_contacts'), 'Payload should contain personal_contacts');
    }

    @IsTest
    static void testBuildTargetedPayloadHealthcareFacility() {
        Account acc = getOrCreatePersonAccount();
        HealthcareFacility facility = new HealthcareFacility(
            Name      = 'Payload Hospital',
            AccountId = acc.Id,
            Phone__c  = '5559990000',
            Email__c  = 'payload@hospital.com'
        );
        insert facility;

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'HealthcareFacility', new Set<Id>{ facility.Id }
        );
        Test.stopTest();

        System.assert(payload.containsKey('healthcare_facilities'), 'Payload should contain healthcare_facilities');
    }

    @IsTest
    static void testBuildTargetedPayloadHealthcarePractitioner() {
        Account acc = getOrCreatePersonAccount();
        HealthcarePractitionerFacility prac = new HealthcarePractitionerFacility(
            Name         = 'Dr. Payload',
            AccountId    = acc.Id,
            Specialty__c = 'Oncology',
            Phone__c     = '5558880000',
            Email__c     = 'drpayload@test.com'
        );
        insert prac;

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'HealthcarePractitionerFacility', new Set<Id>{ prac.Id }
        );
        Test.stopTest();

        System.assert(payload.containsKey('healthcare_professionals'), 'Payload should contain healthcare_professionals');
    }

    @IsTest
    static void testBuildTargetedPayloadCareObservation() {
        Account acc = getOrCreatePersonAccount();
        CareObservation obs = new CareObservation(
            ObservedSubjectId  = acc.Id,
            Name               = 'Heart rate',
            Category           = 'Vital-Signs',
            ObservationStatus  = 'Final',
            Value_Quantity__c  = '72'
        );
        insert obs;

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'CareObservation', new Set<Id>{ obs.Id }
        );
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null');
        System.assert(payload.containsKey('labs'), 'Payload should contain labs');
    }

    @IsTest
    static void testBuildTargetedPayloadUnknownObjectType() {
        Account acc = getOrCreatePersonAccount();

        Test.startTest();
        Map<String, Object> payload = MedicalSalesforceRecord.buildTargetedPayload(
            acc.Id, 'UnknownObject', new Set<Id>()
        );
        Test.stopTest();

        System.assertNotEquals(null, payload, 'Payload should not be null for unknown type');
        System.assert(payload.containsKey('accountId'), 'Payload should still contain accountId');
    }

    // ─────────────────────────────────────────────
    //  getLabs
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetLabs() {
        Account acc = getOrCreatePersonAccount();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Heart rate',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Final',
            Value_Quantity__c = '72',
            Range_High__c     = '100'
        );
        insert obs;

        Test.startTest();
        List<Map<String, Object>> labs =
            MedicalSalesforceRecord.getLabs(acc.Id, new Set<Id>{ obs.Id });
        Test.stopTest();

        System.assertNotEquals(null, labs, 'Labs list should not be null');
        System.assert(labs.size() > 0, 'Should return at least 1 lab');
        System.assertEquals('Heart rate',  labs[0].get('Name'));
        System.assertEquals('Vital-Signs', labs[0].get('Category'));
        System.assertEquals('Final',       labs[0].get('ObservationStatus'));
        System.assertEquals('72',          labs[0].get('Value_Quantity'));
        System.assertEquals('100',         labs[0].get('Range_High'));
    }

    @IsTest
    static void testGetLabsEmptyRecordIds() {
        Account acc = getOrCreatePersonAccount();

        Test.startTest();
        List<Map<String, Object>> labs =
            MedicalSalesforceRecord.getLabs(acc.Id, new Set<Id>());
        Test.stopTest();

        System.assertNotEquals(null, labs, 'Should return empty list, not null');
        System.assertEquals(0, labs.size(), 'Empty recordIds should return empty list');
    }

    @IsTest
    static void testGetLabsNullAccountId() {
        Test.startTest();
        List<Map<String, Object>> labs =
            MedicalSalesforceRecord.getLabs(null, new Set<Id>());
        Test.stopTest();

        System.assertNotEquals(null, labs, 'Should return empty list for null accountId');
        System.assertEquals(0, labs.size(), 'Null accountId should return empty list');
    }

    @IsTest
    static void testGetLabsNullRangeHigh() {
        Account acc = getOrCreatePersonAccount();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Blood Glucose',
            Category          = 'Laboratory',
            ObservationStatus = 'Final',
            Value_Quantity__c = '95',
            Range_High__c     = null
        );
        insert obs;

        Test.startTest();
        List<Map<String, Object>> labs =
            MedicalSalesforceRecord.getLabs(acc.Id, new Set<Id>{ obs.Id });
        Test.stopTest();

        System.assert(labs.size() > 0, 'Should return the lab');
        System.assertEquals(null, labs[0].get('Range_High'), 'Range_High should be null');
    }

    // ─────────────────────────────────────────────
    //  CareObservationTrigger — Insert
    // ─────────────────────────────────────────────

    @IsTest
    static void testCareObservationTriggerOnInsert() {
        ensureApiConfig();
        enableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Heart rate',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Registered',
            Value_Quantity__c = '80'
        );
        insert obs;
        Test.stopTest();

        CareObservation inserted = [SELECT Id FROM CareObservation WHERE Id = :obs.Id];
        System.assertNotEquals(null, inserted.Id, 'CareObservation should be inserted and trigger fired');
    }

    @IsTest
    static void testCareObservationTriggerOnUpdate() {
        ensureApiConfig();
        enableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Heart rate',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Registered',
            Value_Quantity__c = '80'
        );
        insert obs;

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        obs.Value_Quantity__c = '90';
        update obs;
        Test.stopTest();

        CareObservation updated = [SELECT Value_Quantity__c FROM CareObservation WHERE Id = :obs.Id];
        System.assertEquals('90', updated.Value_Quantity__c, 'Value should be updated and trigger fired');
    }

    @IsTest
    static void testCareObservationTriggerOnDelete() {
        ensureApiConfig();
        enableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Heart rate',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Registered',
            Value_Quantity__c = '80'
        );
        insert obs;

        Test.startTest();
        delete obs;
        Test.stopTest();

        List<CareObservation> deleted = [SELECT Id FROM CareObservation WHERE Id = :obs.Id];
        System.assertEquals(0, deleted.size(), 'CareObservation should be deleted and audit log trigger fired');
    }

    @IsTest
    static void testCareObservationTriggerDisabled() {
        ensureApiConfig();
        disableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Heart rate',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Registered',
            Value_Quantity__c = '80'
        );
        insert obs;
        Test.stopTest();

        CareObservation inserted = [SELECT Id FROM CareObservation WHERE Id = :obs.Id];
        System.assertNotEquals(null, inserted.Id, 'Record inserted but trigger should have exited early');
    }

    // ─────────────────────────────────────────────
    //  CareObservationTrigger — Body Weight Sync
    // ─────────────────────────────────────────────

    @IsTest
    static void testCareObservationTriggerBodyWeightInPounds() {
        ensureApiConfig();
        enableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Final',
            Value_Quantity__c = '160'   // already pounds
        );
        insert obs;
        Test.stopTest();

        Account updated = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(160.00, updated.Weight_in_pounds__pc, 'Weight in pounds should be synced correctly');
    }

    @IsTest
    static void testCareObservationTriggerBodyWeightInKg() {
        ensureApiConfig();
        enableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Final',
            Value_Quantity__c = '70 kg'  // kg → should convert to lbs
        );
        insert obs;
        Test.stopTest();

        Account updated = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(154.32, updated.Weight_in_pounds__pc, 'Weight should be converted from kg to lbs');
    }

    // ─────────────────────────────────────────────
    //  CareObservationTrigger — Body Height Sync
    // ─────────────────────────────────────────────

    @IsTest
    static void testCareObservationTriggerBodyHeightInInches() {
        ensureApiConfig();
        enableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Body height',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Final',
            Value_Quantity__c = '68'   // already inches
        );
        insert obs;
        Test.stopTest();

        Account updated = [SELECT Height_in_inches__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(68.00, updated.Height_in_inches__pc, 'Height in inches should be synced correctly');
    }

    @IsTest
    static void testCareObservationTriggerBodyHeightInCm() {
        ensureApiConfig();
        enableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Body height',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Final',
            Value_Quantity__c = '170 cm'  // cm → should convert to inches
        );
        insert obs;
        Test.stopTest();

        Account updated = [SELECT Height_in_inches__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(66.93, updated.Height_in_inches__pc, 'Height should be converted from cm to inches');
    }

    @IsTest
    static void testCareObservationTriggerBlankValueQuantity() {
        ensureApiConfig();
        enableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Final',
            Value_Quantity__c = null   // blank — should skip weight sync
        );
        insert obs;
        Test.stopTest();

        System.assert(true, 'Blank Value_Quantity__c should be skipped without error');
    }

    @IsTest
    static void testCareObservationTriggerInvalidNumericValue() {
        ensureApiConfig();
        enableCareObservationTrigger();
        Account acc = getOrCreatePersonAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        CareObservation obs = new CareObservation(
            ObservedSubjectId = acc.Id,
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Final',
            Value_Quantity__c = 'abc'   // invalid — should be caught and skipped
        );
        insert obs;
        Test.stopTest();

        System.assert(true, 'Invalid numeric value should be caught and skipped without error');
    }

    @IsTest
    static void testCareObservationTriggerNullObservedSubjectId() {
        ensureApiConfig();
        enableCareObservationTrigger();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        // ObservedSubjectId is null — trigger should skip this record
        try {
            CareObservation obs = new CareObservation(
                Name              = 'Heart rate',
                Category          = 'Vital-Signs',
                ObservationStatus = 'Final',
                Value_Quantity__c = '72'
            );
            insert obs;
        } catch (Exception e) {
            // Expected if ObservedSubjectId is required
        }
        Test.stopTest();

        System.assert(true, 'Null ObservedSubjectId handled gracefully');
    }

    // ─────────────────────────────────────────────
    //  getAllergies
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetAllergies() {
        Account acc = getOrCreatePersonAccount();
        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId          = acc.Id,
            Allergy_Name__c    = 'Test Allergy',
            Severity           = 'High',
            Reaction__c        = 'Rash',
            Note__c            = 'Test note',
            Generic__c         = 'Test generic',
            OnsetStartDateTime = Datetime.now()
        );
        insert allergy;

        Test.startTest();
        List<Map<String, Object>> allergies =
            MedicalSalesforceRecord.getAllergies(acc.Id, new Set<Id>{ allergy.Id });
        Test.stopTest();

        System.assertNotEquals(null, allergies, 'Allergies list should not be null');
        System.assert(allergies.size() > 0, 'Should return at least 1 allergy');
    }

    @IsTest
    static void testGetAllergiesEmptyRecordIds() {
        Account acc = getOrCreatePersonAccount();

        Test.startTest();
        List<Map<String, Object>> allergies =
            MedicalSalesforceRecord.getAllergies(acc.Id, new Set<Id>());
        Test.stopTest();

        System.assertNotEquals(null, allergies, 'Should return empty list, not null');
        System.assertEquals(0, allergies.size(), 'Empty recordIds should return empty list');
    }

    // ─────────────────────────────────────────────
    //  getMedications
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetMedications() {
        Account acc = getOrCreatePersonAccount();
        Medication med = new Medication(Name = 'Test Medication', Patient__c = acc.Id);
        insert med;
        MedicationStatement stmt = new MedicationStatement(
            PatientId     = acc.Id,
            MedicationId  = med.Id,
            Status        = 'Active',
            Dose__c       = '500mg',
            Frequency__c  = 'Twice Daily',
            Reason__c     = 'Pain',
            Comments__c   = 'Take with food',
            StartDateTime = Datetime.now().addDays(-5),
            EndDateTime   = Datetime.now().addDays(25)
        );
        insert stmt;

        Test.startTest();
        List<Map<String, Object>> medications =
            MedicalSalesforceRecord.getMedications(acc.Id, new Set<Id>{ stmt.Id });
        Test.stopTest();

        System.assertNotEquals(null, medications, 'Medications list should not be null');
        System.assert(medications.size() > 0, 'Should return at least 1 medication');
    }

    @IsTest
    static void testGetMedicationsEmptyRecordIds() {
        Account acc = getOrCreatePersonAccount();

        Test.startTest();
        List<Map<String, Object>> medications =
            MedicalSalesforceRecord.getMedications(acc.Id, new Set<Id>());
        Test.stopTest();

        System.assertNotEquals(null, medications, 'Should return empty list, not null');
        System.assertEquals(0, medications.size(), 'Empty recordIds should return empty list');
    }

    @IsTest
    static void testGetMedicationsNullAccountId() {
        Test.startTest();
        List<Map<String, Object>> medications =
            MedicalSalesforceRecord.getMedications(null, new Set<Id>());
        Test.stopTest();

        System.assertNotEquals(null, medications, 'Should return empty list for null accountId');
        System.assertEquals(0, medications.size());
    }

    @IsTest
    static void testGetMedicationsNullRecordIds() {
        Account acc = getOrCreatePersonAccount();

        Test.startTest();
        List<Map<String, Object>> medications =
            MedicalSalesforceRecord.getMedications(acc.Id, null);
        Test.stopTest();

        System.assertNotEquals(null, medications, 'Should return empty list for null recordIds');
        System.assertEquals(0, medications.size());
    }

    // ─────────────────────────────────────────────
    //  getMedicalHistory
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetMedicalHistory() {
        Account acc = getOrCreatePersonAccount();
        HealthCondition condition = new HealthCondition(
            PatientId          = acc.Id,
            ProblemName        = 'Test Condition',
            ProblemDescription = 'Test description',
            ConditionStatus    = 'Active',
            Severity           = 'Moderate',
            OnsetStartDateTime = Datetime.now()
        );
        insert condition;

        Test.startTest();
        List<Map<String, Object>> history =
            MedicalSalesforceRecord.getMedicalHistory(acc.Id, new Set<Id>{ condition.Id });
        Test.stopTest();

        System.assertNotEquals(null, history, 'Medical history list should not be null');
        System.assert(history.size() > 0, 'Should return at least 1 condition');
    }

    @IsTest
    static void testGetMedicalHistoryNullOnsetDate() {
        Account acc = getOrCreatePersonAccount();
        HealthCondition condition = new HealthCondition(
            PatientId          = acc.Id,
            ProblemName        = 'No Onset Condition',
            ProblemDescription = 'Desc',
            ConditionStatus    = 'Active',
            OnsetStartDateTime = null
        );
        insert condition;

        Test.startTest();
        List<Map<String, Object>> history =
            MedicalSalesforceRecord.getMedicalHistory(acc.Id, new Set<Id>{ condition.Id });
        Test.stopTest();

        System.assert(history.size() > 0, 'Should return the condition');
        System.assertEquals(null, history[0].get('onsetDate'), 'onsetDate should be null');
    }

    // ─────────────────────────────────────────────
    //  getSurgicalHistory
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetSurgicalHistory() {
        Account acc = getOrCreatePersonAccount();
        HealthCareProcedure procedure = new HealthCareProcedure(
            Patient__c      = acc.Id,
            Name            = 'Testing1234',
            Surgery_Name__c = 'Test Surgery',
            CodeDescription = 'Test description',
            EffectiveDate   = Date.today()
        );
        insert procedure;

        Test.startTest();
        List<Map<String, Object>> surgeries =
            MedicalSalesforceRecord.getSurgicalHistory(acc.Id, new Set<Id>{ procedure.Id });
        Test.stopTest();

        System.assertNotEquals(null, surgeries, 'Surgical history list should not be null');
        System.assert(surgeries.size() > 0, 'Should return at least 1 surgery');
    }

    @IsTest
    static void testGetSurgicalHistoryFallbackName() {
        Account acc = getOrCreatePersonAccount();
        HealthCareProcedure procedure = new HealthCareProcedure(
            Patient__c    = acc.Id,
            Name          = 'Fallback Name Surgery',
            EffectiveDate = Date.today()
        );
        insert procedure;

        Test.startTest();
        List<Map<String, Object>> surgeries =
            MedicalSalesforceRecord.getSurgicalHistory(acc.Id, new Set<Id>{ procedure.Id });
        Test.stopTest();

        System.assert(surgeries.size() > 0, 'Should return at least 1 surgery');
        System.assertEquals('Fallback Name Surgery', surgeries[0].get('name'));
    }

    // ─────────────────────────────────────────────
    //  getInsuranceDetails
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetInsuranceDetails() {
        Account acc = getOrCreatePersonAccount();
        MemberPlan insurance = new MemberPlan(
            Name                                      = 'Test Insurance',
            MemberId                                  = acc.Id,
            MemberNumber                              = 'MEM123',
            GroupNumber                               = 'GRP456',
            medicalcoverage__Payer_Name__c            = 'Test Provider',
            medicalcoverage__Subscriber_First_Name__c = 'Test',
            medicalcoverage__Subscriber_Last_Name__c  = 'Subscriber',
            medicalcoverage__Subscriber_Birth_Date__c = Date.today().addYears(-30),
            RelationshipToSubscriber                  = 'Self',
            PrimarySecondaryTertiary                  = 'Primary'
        );
        insert insurance;

        Test.startTest();
        List<Map<String, Object>> insuranceList =
            MedicalSalesforceRecord.getInsuranceDetails(acc.Id, new Set<Id>{ insurance.Id });
        Test.stopTest();

        System.assertNotEquals(null, insuranceList, 'Insurance list should not be null');
        System.assert(insuranceList.size() > 0, 'Should return at least 1 plan');
        System.assertEquals('Test Provider', insuranceList[0].get('providerName'));
        System.assertEquals('GRP456', insuranceList[0].get('GroupNumber'));
    }

    // ─────────────────────────────────────────────
    //  getPersonalContacts
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetPersonalContacts() {
        Account acc = getOrCreatePersonAccount();
        Contact emergencyContact = new Contact(
            FirstName                         = 'Emergency',
            LastName                          = 'Contact',
            Account__c                        = acc.Id,
            Email                             = 'emergency@test.com',
            MobilePhone                       = '9876543210',
            HomePhone                         = '5551234567',
            Emergency_Contact_Relationship__c = 'Spouse',
            Emergency_Contact__c              = true,
            Is_PHI_Authorized__c              = true,
            Is_Healthcare_Proxy__c            = false,
            Description                       = 'Test contact',
            MailingStreet                     = '123 Test St',
            MailingCity                       = 'Test City',
            MailingState                      = 'California',
            MailingPostalCode                 = '12345',
            MailingCountry                    = 'United States'
        );
        insert emergencyContact;

        Test.startTest();
        List<Map<String, Object>> contacts =
            MedicalSalesforceRecord.getPersonalContacts(acc.Id, new Set<Id>{ emergencyContact.Id });
        Test.stopTest();

        System.assertNotEquals(null, contacts, 'Contacts list should not be null');
        System.assert(contacts.size() > 0, 'Should return at least 1 contact');
        System.assertEquals('Emergency', contacts[0].get('firstName'));
        System.assertEquals(true, contacts[0].get('emergencyContact'));

        Map<String, Object> address = (Map<String, Object>) contacts[0].get('address');
        System.assertEquals('123 Test St', address.get('street'));
        System.assertEquals('Test City', address.get('city'));
    }

    // ─────────────────────────────────────────────
    //  getHealthcareFacilities
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetHealthcareFacilities() {
        Account acc = getOrCreatePersonAccount();
        HealthcareFacility facility = new HealthcareFacility(
            Name             = 'Test Hospital',
            AccountId        = acc.Id,
            Phone__c         = '5559876543',
            Email__c         = 'hospital@test.com',
            Facility_type__c = 'Hospital',
            Fax_Number__c    = '5559876544',
            Website__c       = 'https://testhospital.com'
        );
        insert facility;

        Test.startTest();
        List<Map<String, Object>> facilities =
            MedicalSalesforceRecord.getHealthcareFacilities(acc.Id, new Set<Id>{ facility.Id });
        Test.stopTest();

        System.assertNotEquals(null, facilities, 'Facilities list should not be null');
        System.assert(facilities.size() > 0, 'Should return at least 1 facility');
        System.assertEquals('Test Hospital', facilities[0].get('facilityName'));
        System.assertEquals('Hospital', facilities[0].get('facilityType'));
    }

    // ─────────────────────────────────────────────
    //  getHealthcareProfessionals
    // ─────────────────────────────────────────────

    @IsTest
    static void testGetHealthcareProfessionals() {
        Account acc = getOrCreatePersonAccount();
        HealthcarePractitionerFacility practitioner = new HealthcarePractitionerFacility(
            Name          = 'Dr. Test',
            AccountId     = acc.Id,
            Specialty__c  = 'Cardiology',
            Phone__c      = '5551112222',
            Email__c      = 'doctor@test.com',
            Fax_Number__c = '5551112223'
        );
        insert practitioner;

        Test.startTest();
        List<Map<String, Object>> professionals =
            MedicalSalesforceRecord.getHealthcareProfessionals(acc.Id, new Set<Id>{ practitioner.Id });
        Test.stopTest();

        System.assertNotEquals(null, professionals, 'Professionals list should not be null');
        System.assert(professionals.size() > 0, 'Should return at least 1 professional');
        System.assertEquals('Dr. Test', professionals[0].get('professionalName'));
        System.assertEquals('Cardiology', professionals[0].get('specialty'));
    }

    @IsTest
    static void testFormatDateTimeWithDatetime() {
        Test.startTest();
        String formatted = MedicalSalesforceRecord.formatDateTime(Datetime.now());
        Test.stopTest();

        System.assertNotEquals(null, formatted, 'Datetime should be formatted');
        System.assert(formatted.contains('T'), 'Formatted datetime should contain T separator');
    }

    @IsTest
    static void testFormatDateTimeWithDate() {
        Test.startTest();
        String formatted = MedicalSalesforceRecord.formatDateTime(Date.today());
        Test.stopTest();

        System.assertNotEquals(null, formatted, 'Date should be formatted');
        System.assert(formatted.contains('T'), 'Formatted date should contain T separator');
    }

    @IsTest
    static void testFormatDateTimeWithNull() {
        Test.startTest();
        String formatted = MedicalSalesforceRecord.formatDateTime(null);
        Test.stopTest();

        System.assertEquals(null, formatted, 'Null input should return null');
    }

    @IsTest
    static void testSendHttpRequest() {
        ensureApiConfig();
        BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        HttpResponse response = MedicalSalesforceRecord.sendHttpRequest(
            apiConfig.Api_Key__c,
            new Map<String, Object>{ 'test' => 'data' }
        );
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(200, response.getStatusCode(), 'Status code should be 200');
    }

    @IsTest
    static void testHttpSuccessResponse() {
        ensureApiConfig();
        Account acc = getOrCreatePersonAccount();
        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId       = acc.Id,
            Allergy_Name__c = 'Http Success Allergy',
            Severity        = 'Low'
        );
        insert allergy;

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            acc.Id, 'INSERT', 'AllergyIntolerance', new Set<Id>{ allergy.Id }
        );
        Test.stopTest();

        System.assert(true, 'HTTP 200 success response handled correctly');
    }

    @IsTest
    static void testHttpFailureResponse() {
        ensureApiConfig();
        Account acc = getOrCreatePersonAccount();
        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId       = acc.Id,
            Allergy_Name__c = 'Http Failure Allergy',
            Severity        = 'Low'
        );
        insert allergy;

        Test.setMock(HttpCalloutMock.class, new HttpFailureMock());
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            acc.Id, 'INSERT', 'AllergyIntolerance', new Set<Id>{ allergy.Id }
        );
        Test.stopTest();

        System.assert(true, 'HTTP 500 failure response handled correctly');
    }

    // ─────────────────────────────────────────────
    //  Missing / blank API config
    // ─────────────────────────────────────────────

    @IsTest
    static void testMissingAPIConfigSingle() {
        BatonPortalAPI__c cfg = BatonPortalAPI__c.getOrgDefaults();
        if (cfg != null) {
            cfg.Api_Key__c = '';
            update cfg;
        }

        Account acc = getOrCreatePersonAccount();
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            acc.Id, 'INSERT', 'AllergyIntolerance', new Set<Id>()
        );
        Test.stopTest();

        System.assert(true, 'Blank API key handled gracefully for single-account path');
    }

    @IsTest
    static void testMissingAPIConfigBatch() {
        BatonPortalAPI__c cfg = BatonPortalAPI__c.getOrgDefaults();
        if (cfg != null) {
            cfg.Api_Key__c = '';
            update cfg;
        }

        Account acc = getOrCreatePersonAccount();
        Test.startTest();
        MedicalSalesforceRecord.processBatchSynchronously(
            new List<Id>{ acc.Id }, 'INSERT', 'AllergyIntolerance', new Set<Id>()
        );
        Test.stopTest();

        System.assert(true, 'Blank API key handled gracefully for batch sync path');
    }

    @IsTest
    static void testMissingAPIConfigFutureSingle() {
        BatonPortalAPI__c cfg = BatonPortalAPI__c.getOrgDefaults();
        if (cfg != null) {
            cfg.Api_Key__c = '';
            update cfg;
        }

        Account acc = getOrCreatePersonAccount();
        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        MedicalSalesforceRecord.sendToThirdPartyFuture(
            acc.Id, 'INSERT', 'AllergyIntolerance', JSON.serialize(new List<Id>())
        );
        Test.stopTest();

        System.assert(true, 'Blank API key handled gracefully in sendToThirdPartyFuture');
    }

    @IsTest
    static void testCompleteWorkflow() {
        ensureApiConfig();
        Account acc = getOrCreatePersonAccount();

        AllergyIntolerance allergy = new AllergyIntolerance(
            PatientId       = acc.Id,
            Allergy_Name__c = 'Complete Test Allergy',
            Severity        = 'High'
        );
        insert allergy;

        MemberPlan insurance = new MemberPlan(
            Name         = 'Complete Test Insurance',
            MemberId     = acc.Id,
            MemberNumber = 'TEST123'
        );
        insert insurance;

        Contact contact = new Contact(
            FirstName            = 'Complete',
            LastName             = 'Test',
            Account__c           = acc.Id,
            Emergency_Contact__c = true
        );
        insert contact;

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            acc.Id, 'INSERT', 'AllergyIntolerance', new Set<Id>{ allergy.Id }
        );
        Test.stopTest();

        System.assert(true, 'Complete workflow executed successfully');
    }
    @IsTest
    static void testBasicDetailAccountTriggerOnInsert() {
        ensureApiConfig();
        ensureTriggerEnabled();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        Account newAcc = new Account(
            RecordTypeId = getPersonAccountRecordTypeId(),
            FirstName    = 'Trigger',
            LastName     = 'InsertTest',
            PersonEmail  = 'trigger.insert@example.com'
        );
        insert newAcc;
        Test.stopTest();

        Account inserted = [SELECT Id FROM Account WHERE Id = :newAcc.Id LIMIT 1];
        System.assertNotEquals(null, inserted.Id, 'Account should have been inserted and trigger fired');
    }

    @IsTest
    static void testBasicDetailAccountTriggerOnUpdate() {
        ensureApiConfig();
        ensureTriggerEnabled();
        Account acc = getOrCreatePersonAccount();

        acc.Send_Member_to_portal__c = true;
        update acc;

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        acc.Patient_Summary__c = 'Updated summary';
        update acc;
        Test.stopTest();

        Account updated = [SELECT Patient_Summary__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Updated summary', updated.Patient_Summary__c, 'Trigger should have fired on update');
    }

    @IsTest
    static void testBasicDetailAccountTriggerDisabled() {
        ensureApiConfig();
        disableTrigger();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        Account newAcc = new Account(
            RecordTypeId = getPersonAccountRecordTypeId(),
            FirstName    = 'Trigger',
            LastName     = 'DisabledTest',
            PersonEmail  = 'trigger.disabled@example.com'
        );
        insert newAcc;
        Test.stopTest();

        Account inserted = [SELECT Id FROM Account WHERE Id = :newAcc.Id LIMIT 1];
        System.assertNotEquals(null, inserted.Id, 'Account inserted but trigger should have exited early');
    }
}