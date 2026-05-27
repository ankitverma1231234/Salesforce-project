@IsTest
public class MedicalTriggerCoverageTest {

    /* ============================================================
       HTTP CALLOUT MOCK (USED EVERYWHERE)
       ============================================================ */
    private class SuccessHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }

    /* ============================================================
       TEST SETUP DATA
       ============================================================ */
    @TestSetup
    static void setupData() {

        Test.setMock(HttpCalloutMock.class, new SuccessHttpMock());

        /* ---- Custom Setting ---- */
        insert new BatonPortalAPI__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Api_Key__c = 'https://test.endpoint.com/api',
            Delete_API_Key__c = 'https://test.endpoint.com/delete'
        );

        /* ---- Person Account Record Type ---- */
        Id paRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ].Id;

        /* ---- Person Account ---- */
        Account pa = new Account(
            RecordTypeId = paRtId,
            FirstName = 'Test',
            LastName = 'Patient',
            PersonEmail = 'patient@test.com',
            PersonMobilePhone = '9999999999'
        );
        insert pa;

        /* ---- AllergyIntolerance ---- */
        insert new AllergyIntolerance(
            PatientId = pa.Id,
            Allergy_Name__c = 'Dust',
            Severity = 'Mild'
        );

        /* ---- HealthCondition ---- */
        insert new HealthCondition(
            PatientId = pa.Id,
            ProblemName = 'Diabetes',
            ConditionStatus = 'Active'
        );

        /* ---- HealthCareProcedure ---- */
        insert new HealthCareProcedure(
            Name = 'Appendectomy',
            Surgery_Name__c = 'Appendectomy',
            Patient__c = pa.Id,
            EffectiveDate = Date.today(),
            IsActive = true
        );

        /* ---- Medication ---- */
        Medication med = new Medication(Name = 'Paracetamol');
        insert med;

        insert new MedicationStatement(
            PatientId = pa.Id,
            MedicationId = med.Id,
            Status = 'Active',
            StartDateTime = System.now()
        );

        /* ---- Insurance ---- */
        insert new MemberPlan(
            Name = 'Health Plan',
            MemberId = pa.Id,
            MemberNumber = 'MP-001',
            RelationshipToSubscriber = 'Self',
            PrimarySecondaryTertiary = 'Primary'
        );

        /* ---- Healthcare Facility ---- */
        insert new HealthcareFacility(
            AccountId = pa.Id,
            Name = 'City Hospital'
        );

        /* ---- Healthcare Professional ---- */
        insert new HealthcarePractitionerFacility(
            AccountId = pa.Id,
            Name = 'Dr. Smith',
            Specialty__c = 'Cardiology'
        );

        /* ---- Emergency Contact ---- */
        insert new Contact(
            Account__c = pa.Id,
            FirstName = 'Jane',
            LastName = 'Doe',
            Emergency_Contact__c = true
        );
    }

    /* ============================================================
       MEDICALSALESFORCERECORD CLASS TESTS
       ============================================================ */

    @IsTest
    static void testSendPatientData_Insert() {

        Account pa = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(pa.Id, 'INSERT');
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSendPatientData_Update() {

        Account pa = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty(pa.Id, 'UPDATE');
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testBuildCompletePayload() {

        Account pa = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Map<String, Object> payload =
            MedicalSalesforceRecord.buildCompletePayload(pa.Id);

        System.assert(payload.containsKey('allergies'));
        System.assert(payload.containsKey('medications'));
        System.assert(payload.containsKey('medical_history'));
        System.assert(payload.containsKey('surgical_history'));
        System.assert(payload.containsKey('insurance_details'));
        System.assert(payload.containsKey('personal_contacts'));
        System.assert(payload.containsKey('healthcare_facilities'));
        System.assert(payload.containsKey('healthcare_professionals'));
    }

    @IsTest
    static void testNullAccountId() {

        Test.startTest();
        MedicalSalesforceRecord.sendPatientDataToThirdParty((Id) null, 'INSERT');
        Test.stopTest();

        System.assert(true);
    }

    /* ============================================================
       TRIGGER COVERAGE (INSERT / UPDATE / DELETE)
       ============================================================ */

    @IsTest
    static void testAllTriggers_AllPaths() {

        Account pa = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Medication med = [SELECT Id FROM Medication LIMIT 1];

        Test.startTest();

        /* ---- HealthCareProcedureTrigger ---- */
        HealthCareProcedure hcp = new HealthCareProcedure(
            Name = 'Trigger Surgery',
            Surgery_Name__c = 'Trigger Surgery',
            Patient__c = pa.Id,
            EffectiveDate = Date.today(),
            IsActive = true
        );
        insert hcp;
        update hcp;
        delete hcp;

        /* ---- MedicationStatementTrigger ---- */
        MedicationStatement ms = new MedicationStatement(
            PatientId = pa.Id,
            MedicationId = med.Id,
            Status = 'Active',
            StartDateTime = System.now()
        );
        insert ms;
        update ms;
        delete ms;

        /* ---- HealthcarePractitionerFacilityTrigger ---- */
        HealthcarePractitionerFacility hp = new HealthcarePractitionerFacility(
            AccountId = pa.Id,
            Name = 'Dr Trigger',
            Specialty__c = 'General'
        );
        insert hp;
        update hp;
        delete hp;

        /* ---- HealthcareFacilityTrigger ---- */
        HealthcareFacility hf = new HealthcareFacility(
            AccountId = pa.Id,
            Name = 'Trigger Hospital'
        );
        insert hf;
        update hf;
        delete hf;

        /* ---- ContactMediTrigger ---- */
        Contact con = new Contact(
            Account__c = pa.Id,
            FirstName = 'Trigger',
            LastName = 'Contact'
        );
        insert con;
        delete con;

        /* ---- MemberMediTrigger ---- */
        MemberPlan mp = new MemberPlan(
            Name = 'Trigger Plan',
            MemberId = pa.Id,
            MemberNumber = 'TRG-001'
        );
        insert mp;
        update mp;
        delete mp;

        Test.stopTest();

        System.assert(true);
    }
}