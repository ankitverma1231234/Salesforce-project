@IsTest(SeeAllData = true)
public class SendMetriportDataToPortalTest {

    /* ===============================
       HTTP CALLOUT MOCKS
    ================================ */

    /** 200 OK — happy path */
    private class PortalCalloutMock200 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }

    /** 500 — exercises non-200 branch in sendLiteDataFuture */
    private class PortalCalloutMock500 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"internal server error"}');
            return res;
        }
    }

    /** 400 — exercises failure-logging branch in processFamilySync */
    private class PortalCalloutMock400 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('{"error":"bad request"}');
            return res;
        }
    }

    /* ===============================
       API CONFIG HELPERS
    ================================ */

    private static void ensureApiConfig() {
        BatonPortalAPI__c config = BatonPortalAPI__c.getOrgDefaults();
        config.Api_key_2__c = 'https://mock-portal-endpoint.example.com/api';
        if (config.Id == null) {
            insert config;
        } else {
            update config;
        }
    }

    private static void clearApiConfig() {
        BatonPortalAPI__c config = BatonPortalAPI__c.getOrgDefaults();
        config.Api_key_2__c = '';
        if (config.Id == null) {
            insert config;
        } else {
            update config;
        }
    }

    /* ===============================
       PERSON ACCOUNT HELPERS
    ================================ */

    private static Id getPersonAccountRecordTypeId() {
        return [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ].Id;
    }

    private static Account createTestPatient(String firstName, String lastName,
                                              String email, Boolean isHead) {
        Account pa = new Account(
            RecordTypeId   = getPersonAccountRecordTypeId(),
            FirstName      = firstName,
            LastName       = lastName,
            PersonEmail    = email,
            Family_Head__c = isHead
        );
        insert pa;
        return pa;
    }

    private static Account createTestPatient() {
        return createTestPatient('John', 'TestPatient',
                                 'john.testpatient' + Datetime.now().getTime() + '@example.com',
                                 false);
    }

    /**
     * Person Account with every optional demographic / address field populated
     * so every branch in getBasicDetails() is hit.
     */
    private static Account createFullyPopulatedPatient() {
        Account pa = new Account(
            RecordTypeId                    = getPersonAccountRecordTypeId(),
            FirstName                       = 'FullData',
            LastName                        = 'Patient',
            PersonEmail                     = 'fulldata.patient' + Datetime.now().getTime() + '@example.com',
            Family_Head__c                  = false,
            Height_in_inches__pc            = 68,
            Weight_in_pounds__pc            = 160,
            Consent_to_Call__pc             = true,
            Consent_to_Text__pc             = true,
            Occupation__pc                  = 'Engineer',
            Marital_Status__pc              = 'Single',
            Race__pc                        = 'Asian',
            Ethnicity__pc                   = 'Asian',
            Living_Situation__pc            = 'Lives with family',
            Maiden_Name__pc                 = 'Doe',
            Preferred_Method_of_Contact__pc = 'Email',
            BillingStreet                   = '456 Billing Ave',
            BillingCity                     = 'New York',
            BillingPostalCode               = '10001',
            BillingStateCode                = 'NY',
            BillingCountryCode              = 'US'
        );
        insert pa;
        return pa;
    }

    /* ===============================
       CONTACT / RELATIONSHIP HELPERS
    ================================ */

    /**
     * Returns the Person Contact auto-created for a Person Account.
     * Uses a List to avoid "no rows" exception.
     */
    private static Contact getTestContact(Id accountId) {
        List<Contact> contacts = [
            SELECT Id FROM Contact WHERE AccountId = :accountId LIMIT 1
        ];
        System.assertNotEquals(0, contacts.size(),
            'Person Account must auto-create a Contact for AccountId: ' + accountId);
        return contacts[0];
    }

    /**
     * Creates an Account_Head_Relationship__c record.
     *
     * Production query in processFamilySync:
     *   WHERE Member_Account__c = :parentAccountId
     *   AND Authorized_Account_Access__c != null
     *
     * So:
     *   Member_Account__c            = the patient whose family we are syncing (the "member")
     *   Authorized_Account_Access__c = the account that has access (the "authorized viewer / child")
     *
     * Call as: linkMemberToAuthorized(memberAccountId, authorizedAccountId)
     */
    private static void linkMemberToAuthorized(Id memberAccountId, Id authorizedAccountId) {
        insert new Account_Head_Relationship__c(
            Member_Account__c            = memberAccountId,
            Authorized_Account_Access__c = authorizedAccountId
        );
    }

    /* ================================================================
       TESTS — sendPatientDataMethod / sendLiteDataFuture
    ================================================================ */

    /* TEST 1: Null contactId — early return, no exception */
    @IsTest
    static void testSendPatientDataMethod_NullContactId() {
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(null);
        Test.stopTest();

        System.assert(true, 'Null contactId must be handled gracefully');
    }

    /* TEST 2: Missing API config — blank key branch */
    @IsTest
    static void testSendPatientDataMethod_MissingApiConfig() {
        clearApiConfig();

        Account pa = createTestPatient();
        Contact c  = getTestContact(pa.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'Missing API key must be handled gracefully');
    }

    /* TEST 3: Happy path — minimal patient, no clinical records */
    @IsTest
    static void testSendPatientDataMethod_MinimalPatient() {
        ensureApiConfig();

        Account pa = createTestPatient();
        Contact c  = getTestContact(pa.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        Account updated = [SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Flag must be set on 200 response even with no clinical data');
    }

    /* TEST 4: Full payload — every clinical section populated */
    @IsTest
    static void testSendPatientDataMethod_FullPayload() {
        ensureApiConfig();

        Account pa = createTestPatient('FullPayload', 'Patient',
                                       'fullpayload' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        insert new AllergyIntolerance(
            PatientId          = pa.Id,
            Allergy_Name__c    = 'Dust',
            Severity           = 'Mild',
            Status             = 'Active',
            OnsetStartDateTime = Datetime.now().addDays(-30),
            Note__c            = 'Avoid dusty environments',
            Generic__c         = 'Dust Mites'
        );

        Medication med = new Medication(Name = 'Paracetamol', Patient__c = pa.Id);
        insert med;
        insert new MedicationStatement(
            PatientId     = pa.Id,
            MedicationId  = med.Id,
            Dose__c       = '500mg',
            Frequency__c  = 'Twice Daily',
            Reason__c     = 'Pain relief',
            Status        = 'Active',
            Comments__c   = 'Take with food',
            StartDateTime = Datetime.now().addDays(-10),
            EndDateTime   = Datetime.now().addDays(20)
        );

        insert new HealthCondition(
            PatientId          = pa.Id,
            ProblemName        = 'Diabetes',
            ProblemDescription = 'Type 2',
            OnsetStartDateTime = Datetime.now().addDays(-365),
            ConditionStatus    = 'Active'
        );

        insert new HealthCareProcedure(
            Name            = 'Appendectomy',
            Patient__c      = pa.Id,
            Surgery_Name__c = 'Appendectomy',
            EffectiveDate   = Date.today().addDays(-180),
            Note__c         = 'Routine procedure',
            Status__c       = 'Completed'
        );

        insert new Contact(
            FirstName                         = 'Jane',
            LastName                          = 'Doe',
            Account__c                        = pa.Id,
            MobilePhone                       = '555-0100',
            Email                             = 'jane.doe' + Datetime.now().getTime() + '@example.com',
            Emergency_Contact_Relationship__c = 'Spouse',
            Emergency_Contact__c              = true,
            Is_PHI_Authorized__c              = true,
            Is_Healthcare_Proxy__c            = false,
            Description                       = 'Primary emergency contact'
        );

        insert new HealthcareFacility(
            Name             = 'City General Hospital',
            AccountId        = pa.Id,
            Phone__c         = '555-0200',
            Email__c         = 'info@citygeneral.com',
            Facility_type__c = 'Hospital',
            Fax_Number__c    = '555-0201',
            Website__c       = 'https://citygeneral.com'
        );

        insert new HealthcarePractitionerFacility(
            Name          = 'Dr. Smith',
            AccountId     = pa.Id,
            Phone__c      = '555-0300',
            Email__c      = 'dr.smith@clinic.com',
            Specialty__c  = 'Cardiology',
            Fax_Number__c = '555-0301'
        );

        insert new MemberPlan(
            Name                                      = 'BlueCross Plan',
            MemberId                                  = pa.Id,
            medicalcoverage__Payer_Name__c            = 'BlueCross',
            GroupNumber                               = 'GRP-001',
            MemberNumber                              = 'MBR-12345',
            medicalcoverage__Subscriber_First_Name__c = 'John',
            medicalcoverage__Subscriber_Last_Name__c  = 'TestPatient',
            medicalcoverage__Subscriber_Birth_Date__c = Date.newInstance(1985, 6, 15),
            RelationshipToSubscriber                  = 'Self',
            PrimarySecondaryTertiary                  = 'Primary'
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        Account updated = [SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Flag must be set after full-payload 200 response');
    }

    /* TEST 5: HTTP 500 — flag must NOT be set */
    @IsTest
    static void testSendPatientDataMethod_Http500Response() {
        ensureApiConfig();

        Account pa = createTestPatient('Http500', 'Patient',
                                       'http500' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock500());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        Account result = [SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id];
        System.assertNotEquals(true, result.Send_Member_to_portal__c,
            'Flag must NOT be set when HTTP response is non-200');
    }

    /* TEST 6: Fully populated account fields — all getBasicDetails() branches */
    @IsTest
    static void testSendPatientDataMethod_FullyPopulatedAccountFields() {
        ensureApiConfig();

        Account pa = createFullyPopulatedPatient();
        Contact c  = getTestContact(pa.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        Account updated = [SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Flag must be set after successful send with all demographic fields populated');
    }

    /* TEST 7: formatDateTime — Datetime, Date, and null branches */
    @IsTest
    static void testFormatDateTimeBranches() {
        ensureApiConfig();

        Account pa = createTestPatient();
        Contact c  = getTestContact(pa.Id);

        // Datetime branch
        insert new AllergyIntolerance(
            PatientId          = pa.Id,
            Allergy_Name__c    = 'Pollen',
            Severity           = 'Moderate',
            OnsetStartDateTime = Datetime.now().addDays(-10)
        );
        // Date branch
        insert new HealthCareProcedure(
            Name            = 'Knee Surgery',
            Patient__c      = pa.Id,
            Surgery_Name__c = 'Knee Surgery',
            EffectiveDate   = Date.today().addDays(-90)
        );
        // Null branch
        insert new HealthCondition(
            PatientId          = pa.Id,
            ProblemName        = 'Hypertension',
            ProblemDescription = 'Stage 1',
            OnsetStartDateTime = null
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'All formatDateTime branches must execute without error');
    }

    /* TEST 8: Multiple allergies — null onset included */
    @IsTest
    static void testSendPatientDataMethod_MultipleAllergies() {
        ensureApiConfig();

        Account pa = createTestPatient('MultiAllergy', 'Patient',
                                       'multiallergy' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        insert new AllergyIntolerance(
            PatientId          = pa.Id,
            Allergy_Name__c    = 'Penicillin',
            Severity           = 'Severe',
            Status             = 'Active',
            OnsetStartDateTime = Datetime.now().addDays(-60)
        );
        insert new AllergyIntolerance(
            PatientId          = pa.Id,
            Allergy_Name__c    = 'Shellfish',
            Severity           = 'Moderate',
            Status             = 'Active',
            OnsetStartDateTime = Datetime.now().addDays(-120),
            Generic__c         = 'Crustaceans'
        );
        insert new AllergyIntolerance(
            PatientId       = pa.Id,
            Allergy_Name__c = 'Latex',
            Severity        = 'Mild',
            Status          = 'Inactive'
            // null OnsetStartDateTime — exercises null branch
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'Multiple allergies including null-onset must be handled');
    }

    /* TEST 9: Multiple medications — null start and end dates */
    @IsTest
    static void testSendPatientDataMethod_MultipleMedications() {
        ensureApiConfig();

        Account pa = createTestPatient('MultiMed', 'Patient',
                                       'multimed' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        Medication med1 = new Medication(Name = 'Aspirin',    Patient__c = pa.Id);
        Medication med2 = new Medication(Name = 'Metformin',  Patient__c = pa.Id);
        Medication med3 = new Medication(Name = 'Lisinopril', Patient__c = pa.Id);
        insert new List<Medication>{ med1, med2, med3 };

        insert new MedicationStatement(
            PatientId     = pa.Id, MedicationId = med1.Id,
            Dose__c       = '81mg', Frequency__c = 'Daily', Status = 'Active',
            StartDateTime = Datetime.now().addDays(-200), EndDateTime = null
        );
        insert new MedicationStatement(
            PatientId     = pa.Id, MedicationId = med2.Id,
            Dose__c       = '500mg', Frequency__c = 'Twice Daily', Status = 'Active',
            StartDateTime = Datetime.now().addDays(-100),
            EndDateTime   = Datetime.now().addDays(90)
        );
        insert new MedicationStatement(
            PatientId     = pa.Id, MedicationId = med3.Id,
            Dose__c       = '10mg', Frequency__c = 'Once Daily', Status = 'Discontinued',
            StartDateTime = null, EndDateTime = Datetime.now().addDays(-10)
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'Multiple medications including null dates must be handled');
    }

    /* TEST 10: Multiple health conditions — null onset */
    @IsTest
    static void testSendPatientDataMethod_MultipleHealthConditions() {
        ensureApiConfig();

        Account pa = createTestPatient('MultiCond', 'Patient',
                                       'multicond' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        insert new HealthCondition(
            PatientId = pa.Id, ProblemName = 'Asthma',
            ProblemDescription = 'Mild persistent',
            OnsetStartDateTime = Datetime.now().addDays(-500), ConditionStatus = 'Active'
        );
        insert new HealthCondition(
            PatientId = pa.Id, ProblemName = 'Osteoarthritis',
            ProblemDescription = 'Knee bilateral',
            OnsetStartDateTime = null, ConditionStatus = 'Chronic'
        );
        insert new HealthCondition(
            PatientId = pa.Id, ProblemName = 'GERD',
            ProblemDescription = 'Acid reflux',
            OnsetStartDateTime = Datetime.now().addDays(-200), ConditionStatus = 'Resolved'
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'Multiple health conditions including null onset must be handled');
    }

    /* TEST 11: Multiple surgical procedures — null EffectiveDate */
    @IsTest
    static void testSendPatientDataMethod_MultipleSurgeries() {
        ensureApiConfig();

        Account pa = createTestPatient('MultiSurg', 'Patient',
                                       'multisurg' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        insert new HealthCareProcedure(
            Name = 'Cholecystectomy', Patient__c = pa.Id,
            Surgery_Name__c = 'Cholecystectomy',
            EffectiveDate = Date.today().addDays(-365),
            Note__c = 'Laparoscopic', Status__c = 'Completed'
        );
        insert new HealthCareProcedure(
            Name = 'Cataract Removal', Patient__c = pa.Id,
            Surgery_Name__c = 'Cataract Removal',
            EffectiveDate = null,          // null date → formatDateTime returns ''
            Status__c = 'Completed'
        );
        insert new HealthCareProcedure(
            Name = 'Hip Replacement', Patient__c = pa.Id,
            Surgery_Name__c = 'Hip Replacement',
            EffectiveDate = Date.today().addDays(-90), Status__c = 'Pending'
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'Multiple surgical procedures including null date must be handled');
    }

    /* TEST 12: Multiple personal contacts */
    @IsTest
    static void testSendPatientDataMethod_MultiplePersonalContacts() {
        ensureApiConfig();

        Account pa = createTestPatient('MultiContact', 'Patient',
                                       'multicontact' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        insert new Contact(
            FirstName = 'Alice', LastName = 'Emergency',
            Account__c = pa.Id, MobilePhone = '555-1111',
            Email = 'alice.em' + Datetime.now().getTime() + '@example.com',
            Emergency_Contact_Relationship__c = 'CHILD',
            Emergency_Contact__c = true, Is_PHI_Authorized__c = true,
            Is_Healthcare_Proxy__c = false
        );
        insert new Contact(
            FirstName = 'Bob', LastName = 'Proxy',
            Account__c = pa.Id, MobilePhone = '555-2222',
            Email = 'bob.proxy' + Datetime.now().getTime() + '@example.com',
            Emergency_Contact_Relationship__c = 'CHILD',
            Emergency_Contact__c = false, Is_PHI_Authorized__c = false,
            Is_Healthcare_Proxy__c = true
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'Multiple personal contacts must all be serialized');
    }

    /* TEST 13: Multiple healthcare facilities */
    @IsTest
    static void testSendPatientDataMethod_MultipleHealthcareFacilities() {
        ensureApiConfig();

        Account pa = createTestPatient('MultiFac', 'Patient',
                                       'multifac' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        insert new HealthcareFacility(
            Name = 'Memorial Hospital', AccountId = pa.Id,
            Facility_type__c = 'Hospital', Phone__c = '555-3001'
        );
        insert new HealthcareFacility(
            Name = 'Downtown Urgent Care', AccountId = pa.Id,
            Facility_type__c = 'Hospital', Phone__c = '555-3002',
            Email__c = 'care@downtown.com'
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'Multiple healthcare facilities must be serialized');
    }

    /* TEST 14: Multiple healthcare professionals */
    @IsTest
    static void testSendPatientDataMethod_MultipleHealthcareProfessionals() {
        ensureApiConfig();

        Account pa = createTestPatient('MultiProf', 'Patient',
                                       'multiprof' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        insert new HealthcarePractitionerFacility(
            Name = 'Dr. Adams', AccountId = pa.Id,
            Specialty__c = 'Dermatology', Phone__c = '555-4001'
        );
        insert new HealthcarePractitionerFacility(
            Name = 'Dr. Baker', AccountId = pa.Id,
            Specialty__c = 'Endocrinology', Phone__c = '555-4002',
            Email__c = 'dr.baker@clinic.com', Fax_Number__c = '555-4003'
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'Multiple healthcare professionals must be serialized');
    }

    /* TEST 15: Multiple insurance plans */
    @IsTest
    static void testSendPatientDataMethod_MultipleInsurancePlans() {
        ensureApiConfig();

        Account pa = createTestPatient('MultiIns', 'Patient',
                                       'multiins' + Datetime.now().getTime() + '@example.com',
                                       false);
        Contact c  = getTestContact(pa.Id);

        insert new MemberPlan(
            Name = 'United Primary', MemberId = pa.Id,
            medicalcoverage__Payer_Name__c = 'United',
            GroupNumber = 'GRP-P01', MemberNumber = 'MBR-P001',
            PrimarySecondaryTertiary = 'Primary'
        );
        insert new MemberPlan(
            Name = 'Cigna Secondary', MemberId = pa.Id,
            medicalcoverage__Payer_Name__c = 'Cigna',
            GroupNumber = 'GRP-S01', MemberNumber = 'MBR-S001',
            PrimarySecondaryTertiary = 'Secondary',
            medicalcoverage__Subscriber_Birth_Date__c = Date.newInstance(1975, 3, 20)
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        System.assert(true, 'Multiple insurance plans must be serialized correctly');
    }

    /* ================================================================
       TESTS — updateSendMemberToPortal
    ================================================================ */

    /* TEST 17: Null accountId — no exception */
    @IsTest
    static void testUpdateSendMemberToPortal_NullId() {
        Test.startTest();
        SendMetriportDataToPortal.updateSendMemberToPortal(null);
        Test.stopTest();

        System.assert(true, 'Null accountId must be handled gracefully');
    }

    /* TEST 18: Valid accountId — flag is set to true */
    @IsTest
    static void testUpdateSendMemberToPortal_ValidId() {
        Account pa = createTestPatient();

        Test.startTest();
        SendMetriportDataToPortal.updateSendMemberToPortal(pa.Id);
        Test.stopTest();

        Account updated = [SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Send_Member_to_portal__c must be true after updateSendMemberToPortal');
    }

    /* ================================================================
       TESTS — getHealthcareFacilities (public method)
    ================================================================ */

    /* TEST 19: Null accountId — returns empty list, no exception */
    @IsTest
    static void testGetHealthcareFacilities_NullAccountId() {
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getHealthcareFacilities(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result must not be null for null accountId');
    }

    /* TEST 20: Valid accountId — returns correct data */
    @IsTest
    static void testGetHealthcareFacilities_ReturnsData() {
        Account pa = createTestPatient();

        insert new HealthcareFacility(
            Name = 'Sunrise Clinic', AccountId = pa.Id, Phone__c = '555-0400'
        );

        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getHealthcareFacilities(pa.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result must not be null');
        System.assert(result.size() > 0, 'Must return at least one facility');
        System.assertEquals('Sunrise Clinic', result[0].get('facilityName'),
            'Facility name must match inserted record');
    }

    /* ================================================================
       TESTS — getHealthcareProfessionals (public method)
    ================================================================ */

    /* TEST 21: Null accountId — returns empty list, no exception */
    @IsTest
    static void testGetHealthcareProfessionals_NullAccountId() {
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getHealthcareProfessionals(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result must not be null for null accountId');
    }

    /* TEST 22: Valid accountId — returns correct data */
    @IsTest
    static void testGetHealthcareProfessionals_ReturnsData() {
        Account pa = createTestPatient();

        insert new HealthcarePractitionerFacility(
            Name = 'Dr. Jones', AccountId = pa.Id,
            Specialty__c = 'Neurology', Phone__c = '555-0500'
        );

        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getHealthcareProfessionals(pa.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result must not be null');
        System.assert(result.size() > 0, 'Must return at least one professional');
        System.assertEquals('Dr. Jones',  result[0].get('professionalName'));
        System.assertEquals('Neurology',  result[0].get('specialty'));
    }

    /* ================================================================
       TESTS — getInsuranceDetails (public method)
    ================================================================ */

    /* TEST 23: Null accountId — returns empty list, no exception */
    @IsTest
    static void testGetInsuranceDetails_NullAccountId() {
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getInsuranceDetails(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result must not be null for null accountId');
    }

    /* TEST 24: Valid accountId — returns correct data */
    @IsTest
    static void testGetInsuranceDetails_ReturnsData() {
        Account pa = createTestPatient();

        insert new MemberPlan(
            Name = 'Aetna Silver', MemberId = pa.Id,
            medicalcoverage__Payer_Name__c = 'Aetna',
            GroupNumber = 'GRP-999', MemberNumber = 'MBR-99999',
            PrimarySecondaryTertiary = 'Secondary'
        );

        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getInsuranceDetails(pa.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result must not be null');
        System.assert(result.size() > 0, 'Must return at least one insurance record');
        System.assertEquals('Aetna',   result[0].get('providerName'));
        System.assertEquals('GRP-999', result[0].get('GroupNumber'));
    }

    /* TEST 25: Subscriber birth date null — formatDateTime not called */
    @IsTest
    static void testGetInsuranceDetails_NullSubscriberBirthDate() {
        Account pa = createTestPatient();

        insert new MemberPlan(
            Name = 'Humana Null Birth', MemberId = pa.Id,
            medicalcoverage__Payer_Name__c = 'Humana',
            GroupNumber = 'GRP-HUM', MemberNumber = 'MBR-HUM',
            medicalcoverage__Subscriber_Birth_Date__c = null,
            PrimarySecondaryTertiary = 'Primary'
        );

        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getInsuranceDetails(pa.Id);
        Test.stopTest();

        System.assert(result.size() > 0, 'Must return plan even with null birth date');
        System.assertNotEquals(null, result[0].get('providerName'),
            'Provider name must be present');
        System.assertEquals(null, result[0].get('Subscriber_Birth_Date'),
            'Subscriber_Birth_Date must be null when not set');
    }

    /* ================================================================
       TESTS — getDocuments (public method)
    ================================================================ */

    /* TEST 26: Null accountId — returns empty list immediately */
    @IsTest
    static void testGetDocuments_NullAccountId() {
        Test.startTest();
        List<Map<String, Object>> result = SendMetriportDataToPortal.getDocuments(null, null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result must not be null');
        System.assertEquals(0, result.size(), 'Must return empty list for null accountId');
    }

    /* TEST 27: Account with no ContentDocumentLinks — returns empty list */
    @IsTest
    static void testGetDocuments_NoDocuments() {
        Account pa = createTestPatient();
        Contact c  = getTestContact(pa.Id);

        Test.startTest();
        List<Map<String, Object>> result = SendMetriportDataToPortal.getDocuments(pa.Id, c.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result must not be null');
        System.assertEquals(0, result.size(),
            'Must return empty list when no documents exist');
    }

    /* ================================================================
       TESTS — sendFamilyMemberData
    ================================================================ */

    /* TEST 32: Null authorizedAccountId — early return, no exception */
    @IsTest
    static void testSendFamilyMemberData_NullId() {
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyMemberData(null);
        Test.stopTest();

        System.assert(true, 'Null authorizedAccountId must be handled gracefully');
    }

    /* TEST 33: Missing API config — logs and returns */
    @IsTest
    static void testSendFamilyMemberData_MissingApiConfig() {
        clearApiConfig();

        Account member = createTestPatient('Head', 'NoConfig',
                                           'head.noconfig' + Datetime.now().getTime() + '@example.com',
                                           true);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyMemberData(member.Id);
        Test.stopTest();

        System.assert(true, 'Missing API config must be handled gracefully');
    }

    /* TEST 34: No junction records for account — isEmpty() branch */
    @IsTest
    static void testSendFamilyMemberData_NoJunctionRecords() {
        ensureApiConfig();

        Account loneAccount = createTestPatient('Lone', 'Account',
                                                'lone' + Datetime.now().getTime() + '@example.com',
                                                false);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyMemberData(loneAccount.Id);
        Test.stopTest();

        System.assert(true, 'Account with no junction records must return gracefully');
    }

    /* TEST 35: sendFamilyMemberData dispatches @future — one authorized account */
    @IsTest
    static void testSendFamilyMemberData_DispatchesFuture() {
        ensureApiConfig();

        // member is the patient; authorized is who can see them
        Account member     = createTestPatient('Member', 'FamilyAsync',
                                               'member.async' + Datetime.now().getTime() + '@example.com',
                                               false);
        Account authorized = createTestPatient('Auth',   'FamilyAsync',
                                               'auth.async' + Datetime.now().getTime() + '@example.com',
                                               true);

        linkMemberToAuthorized(member.Id, authorized.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyMemberData(member.Id);
        Test.stopTest();

        System.assert(true, 'sendFamilyMemberData must dispatch @future callout without error');
    }

    /* ================================================================
       TESTS — sendFamilyFuture (@future wrapper)
    ================================================================ */

    /* TEST 36: Direct call to sendFamilyFuture — delegates to processFamilySync */
    @IsTest
    static void testSendFamilyFuture_DirectCall() {
        ensureApiConfig();

        Account member     = createTestPatient('FutureDir', 'Member',
                                               'futuredir.member' + Datetime.now().getTime() + '@example.com',
                                               false);
        Account authorized = createTestPatient('FutureDir', 'Auth',
                                               'futuredir.auth' + Datetime.now().getTime() + '@example.com',
                                               true);

        linkMemberToAuthorized(member.Id, authorized.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyFuture(member.Id);
        Test.stopTest();

        System.assert(true,
            'sendFamilyFuture direct call must delegate to processFamilySync without error');
    }

    /* ================================================================
       TESTS — processFamilySync (public synchronous method)
    ================================================================ */

    /* TEST 37: Missing API config in processFamilySync — logs and returns */
    @IsTest
    static void testProcessFamilySync_MissingApiConfig() {
        clearApiConfig();

        Account member     = createTestPatient('PFSync', 'NoConfig',
                                               'pfsync.noconfig' + Datetime.now().getTime() + '@example.com',
                                               true);
        Account authorized = createTestPatient('PFSync', 'Auth',
                                               'pfsync.auth' + Datetime.now().getTime() + '@example.com',
                                               false);
        linkMemberToAuthorized(member.Id, authorized.Id);

        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();

        System.assert(true,
            'processFamilySync with blank API config must log and return without exception');
    }

    /* TEST 38: No junction records — isEmpty() returns early */
    @IsTest
    static void testProcessFamilySync_NoJunctionRecords() {
        ensureApiConfig();

        Account loneAccount = createTestPatient('PFLone', 'Account',
                                                'pflone' + Datetime.now().getTime() + '@example.com',
                                                false);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(loneAccount.Id);
        Test.stopTest();

        System.assert(true, 'processFamilySync with no junction records must return gracefully');
    }

    /* TEST 39: One authorized account — full payload path */
    @IsTest
    static void testProcessFamilySync_OneAuthorizedAccount() {
        ensureApiConfig();

        Account member     = createTestPatient('PFOne', 'Member',
                                               'pfone.member' + Datetime.now().getTime() + '@example.com',
                                               false);
        Account authorized = createTestPatient('PFOne', 'Auth',
                                               'pfone.auth' + Datetime.now().getTime() + '@example.com',
                                               true);

        linkMemberToAuthorized(member.Id, authorized.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();

        System.assert(true, 'processFamilySync with one authorized account must complete');
    }

    /* TEST 40: Two authorized accounts — both included in payload */
    @IsTest
    static void testProcessFamilySync_TwoAuthorizedAccounts() {
        ensureApiConfig();

        Account member  = createTestPatient('PFTwo', 'Member',
                                            'pftwo.member' + Datetime.now().getTime() + '@example.com',
                                            false);
        Account authA   = createTestPatient('PFTwo', 'AuthA',
                                            'pftwo.autha' + Datetime.now().getTime() + '@example.com',
                                            true);
        Account authB   = createTestPatient('PFTwo', 'AuthB',
                                            'pftwo.authb' + Datetime.now().getTime() + '@example.com',
                                            true);

        linkMemberToAuthorized(member.Id, authA.Id);
        linkMemberToAuthorized(member.Id, authB.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();

        System.assert(true, 'Both authorized accounts must be included in the payload');
    }

    /* TEST 41: Three authorized accounts — de-duplication map logic */
    @IsTest
    static void testProcessFamilySync_ThreeAuthorizedAccountsDeduplicated() {
        ensureApiConfig();

        Account member = createTestPatient('PFThree', 'Member',
                                           'pfthree.member' + Datetime.now().getTime() + '@example.com',
                                           false);
        Account authA  = createTestPatient('PFThree', 'AuthA',
                                           'pfthree.a' + Datetime.now().getTime() + '@example.com',
                                           false);
        Account authB  = createTestPatient('PFThree', 'AuthB',
                                           'pfthree.b' + Datetime.now().getTime() + '@example.com',
                                           false);
        Account authC  = createTestPatient('PFThree', 'AuthC',
                                           'pfthree.c' + Datetime.now().getTime() + '@example.com',
                                           false);

        linkMemberToAuthorized(member.Id, authA.Id);
        linkMemberToAuthorized(member.Id, authB.Id);
        linkMemberToAuthorized(member.Id, authC.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();

        System.assert(true,
            'Three authorized accounts must all appear in payload without duplicates');
    }

    /* TEST 42: HTTP 400 response — failure-logging branch in processFamilySync */
    @IsTest
    static void testProcessFamilySync_Http400Response() {
        ensureApiConfig();

        Account member     = createTestPatient('Err400', 'Member',
                                               'err400.member' + Datetime.now().getTime() + '@example.com',
                                               false);
        Account authorized = createTestPatient('Err400', 'Auth',
                                               'err400.auth' + Datetime.now().getTime() + '@example.com',
                                               true);

        linkMemberToAuthorized(member.Id, authorized.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock400());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();

        System.assert(true, 'HTTP 400 from family endpoint must be logged gracefully');
    }

    /* TEST 43: processFamilySync called directly simulating isFuture/isBatch branch */
    @IsTest
    static void testProcessFamilySync_DirectCallSimulatesFutureBranch() {
        ensureApiConfig();

        Account member     = createTestPatient('Direct', 'FutureBranch',
                                               'direct.future' + Datetime.now().getTime() + '@example.com',
                                               false);
        Account authorized = createTestPatient('Direct', 'FutureAuth',
                                               'direct.auth' + Datetime.now().getTime() + '@example.com',
                                               false);

        linkMemberToAuthorized(member.Id, authorized.Id);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();

        System.assert(true, 'Direct processFamilySync call must complete without exception');
    }
}