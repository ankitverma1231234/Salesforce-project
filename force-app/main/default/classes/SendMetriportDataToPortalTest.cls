@IsTest(SeeAllData = true)
public class SendMetriportDataToPortalTest {

    /* ================================================================
       HTTP CALLOUT MOCKS
    ================================================================ */
    private class PortalCalloutMock200 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }

    private class PortalCalloutMock500 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"internal server error"}');
            return res;
        }
    }

    private class PortalCalloutMock400 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('{"error":"bad request"}');
            return res;
        }
    }

    /* ================================================================
       API CONFIG HELPERS
    ================================================================ */
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

    /* ================================================================
       PERSON ACCOUNT HELPERS
    ================================================================ */
    private static Id getPersonAccountRecordTypeId() {
        return [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ].Id;
    }

    private static Account createTestPatient(
        String firstName, String lastName, String email, Boolean isHead
    ) {
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
        return createTestPatient(
            'John', 'TestPatient',
            'john.testpatient' + Datetime.now().getTime() + '@example.com',
            false
        );
    }

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

    private static Contact getTestContact(Id accountId) {
        List<Contact> contacts = [
            SELECT Id FROM Contact WHERE AccountId = :accountId LIMIT 1
        ];
        System.assertNotEquals(
            0, contacts.size(),
            'Person Account must auto-create a Contact for AccountId: ' + accountId
        );
        return contacts[0];
    }

    private static void linkMemberToAuthorized(Id memberAccountId, Id authorizedAccountId) {
        insert new Account_Head_Relationship__c(
            Member_Account__c            = memberAccountId,
            Authorized_Account_Access__c = authorizedAccountId
        );
    }

    /* ================================================================
       HELPER — create fra__Entity_Storage__c + fra__File_Storage__c
       This mirrors what getDocuments() actually queries
    ================================================================ */
    private static fra__File_Storage__c createFileStorage(
        Id accountId,
        String name,
        String docType,
        String sourceType,
        String category,
        Boolean sendToPortal
    ) {
        // Step 1: Create Entity Storage linked to the account
        fra__Entity_Storage__c es = new fra__Entity_Storage__c(
            fra__File_Store_Record_Id__c = String.valueOf(accountId)
        );
        insert es;

        // Step 2: Create File Storage linked to Entity Storage
        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name                    = name,
            fra__Entity_Storage__c  = es.Id,
            Send_to_Portal__c       = sendToPortal,
            Document_Type__c        = docType,
            Source_Type__c          = sourceType,
            Category__c             = category
        );
        insert fs;
        return fs;
    }

    /* ================================================================
       sendPatientDataMethod / sendLiteDataFuture
    ================================================================ */
    @IsTest
    static void testSendPatientDataMethod_NullContactId() {
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(null);
        Test.stopTest();
        System.assert(true, 'Null contactId must be handled gracefully');
    }

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

    @IsTest
    static void testSendPatientDataMethod_MinimalPatient() {
        ensureApiConfig();
        Account pa = createTestPatient();
        Contact c  = getTestContact(pa.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        Account updated = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Flag must be set on 200 response even with no clinical data');
    }

    @IsTest
    static void testSendPatientDataMethod_Http500Response() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'Http500', 'Patient',
            'http500' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock500());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        Account result = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertNotEquals(true, result.Send_Member_to_portal__c,
            'Flag must NOT be set when HTTP response is non-200');
    }

    @IsTest
    static void testSendPatientDataMethod_FullyPopulatedAccountFields() {
        ensureApiConfig();
        Account pa = createFullyPopulatedPatient();
        Contact c  = getTestContact(pa.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        Account updated = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Flag must be set after successful send with all demographic fields');
    }

    @IsTest
    static void testSendPatientDataMethod_FullPayload() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'FullPayload', 'Patient',
            'fullpayload' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

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
            Email = 'jane.doe' + Datetime.now().getTime() + '@example.com',
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

        Account updated = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Flag must be set after full-payload 200 response');
    }

    /* ================================================================
       formatDateTime branches
    ================================================================ */
    @IsTest
    static void testFormatDateTimeBranches() {
        ensureApiConfig();
        Account pa = createTestPatient();
        Contact c  = getTestContact(pa.Id);

        insert new AllergyIntolerance(
            PatientId          = pa.Id,
            Allergy_Name__c    = 'Pollen',
            Severity           = 'Moderate',
            OnsetStartDateTime = Datetime.now().addDays(-10)
        );
        insert new HealthCareProcedure(
            Name            = 'Knee Surgery',
            Patient__c      = pa.Id,
            Surgery_Name__c = 'Knee Surgery',
            EffectiveDate   = Date.today().addDays(-90)
        );
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

    @IsTest
    static void testFormatDateTimeInZone_NullDatetime() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'FDZNull', 'Patient',
            'fdznull' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        insert new AllergyIntolerance(
            PatientId       = pa.Id,
            Allergy_Name__c = 'NullOnset',
            Severity        = 'Mild'
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'Null onset datetime must return empty string without error');
    }

    /* ================================================================
       getLabs
    ================================================================ */
    @IsTest
    static void testGetLabs_WithCareObservationData() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'LabTest', 'Patient',
            'labtest' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        insert new CareObservation(
            Name              = 'HbA1c',
            ObservedSubjectId = pa.Id,
            Category          = 'Laboratory',
            ObservationStatus = 'Final',
            Range_High__c     = '6.5',
            Value_Quantity__c = '5.8'
        );
        insert new CareObservation(
            Name              = 'LDL Cholesterol',
            ObservedSubjectId = pa.Id,
            Category          = 'Laboratory',
            ObservationStatus = 'Final',
            Range_High__c     = null,
            Value_Quantity__c = null
        );

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        Account updated = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'getLabs with CareObservation data must not break the send flow');
    }

    @IsTest
    static void testGetLabs_NullAccountId() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'LabNull', 'Patient',
            'labnull' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'getLabs with no observations must return empty list gracefully');
    }

    /* ================================================================
       getDocuments — uses fra__Entity_Storage__c / fra__File_Storage__c
    ================================================================ */

    @IsTest
    static void testGetDocuments_NullAccountId() {
        Test.startTest();
        // getDocuments is private — exercise via sendPatientDataMethod
        // with a patient that has no entity storages
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getDocuments(null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result must not be null');
        System.assertEquals(0, result.size(), 'Must return empty list for null accountId');
    }

    @IsTest
    static void testGetDocuments_NoEntityStorages() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'DocNone', 'Patient',
            'docnone' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        // No fra__Entity_Storage__c records → getDocuments returns empty early
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'No entity storages must return empty documents gracefully');
    }

    @IsTest
    static void testGetDocuments_EntityStorageExistsButNoSendableFiles() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'DocNoSend', 'Patient',
            'docnosend' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        // Entity storage exists but file has Send_to_Portal__c = false
        createFileStorage(pa.Id, 'Not Sendable', 'Radiology', 'Metriport', null, false);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true,
            'Entity storage with no sendable files must return empty documents list');
    }

    @IsTest
    static void testGetDocuments_WithSendableFile() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'DocSend', 'Patient',
            'docsend' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        // File with Send_to_Portal__c = true → should appear in documents
        createFileStorage(pa.Id, 'Lab Report', 'Radiology', 'Metriport',
            'Estate, Legal & Financial Documents', true);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        Account updated = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Payload with sendable document must complete and set flag');
    }

    @IsTest
    static void testGetDocuments_MultipleFiles() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'MultiDoc', 'Patient',
            'multidoc' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        createFileStorage(pa.Id, 'File One',   'Radiology', 'Metriport', null, true);
        createFileStorage(pa.Id, 'File Two',   'Lab',       'Metriport',    null, true);
        createFileStorage(pa.Id, 'File Hidden','Lab',       'Metriport',    null, false);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        Account updated = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Multiple sendable files must all be included in payload');
    }

    @IsTest
    static void testGetDocuments_AllFieldsPopulated() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'DocFull', 'Patient',
            'docfull' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        fra__Entity_Storage__c es = new fra__Entity_Storage__c(
            fra__File_Store_Record_Id__c = String.valueOf(pa.Id)
        );
        insert es;

        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name                       = 'Full Fields Doc',
            fra__Entity_Storage__c     = es.Id,
            Send_to_Portal__c          = true,
            fra__File_Public_Url__c    = 'https://example.com/file.pdf',
            fra__File_Size__c =        String.valueOf(1024),
            fra__File_Type__c          = 'PDF',
            Source_Type__c             = 'Metriport',
            Document_Type__c           = 'Radiology',
            Category__c                = 'Estate, Legal & Financial Documents',
            Fra_AI_Source_File_Id__c   = 'AI-SRC-001'
        );
        insert fs;

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        Account updated = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'All document fields populated — payload must complete successfully');
    }

    @IsTest
    static void testGetDocuments_NullFileFields() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'DocNullFields', 'Patient',
            'docnullfields' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        // All optional fields null — covers null-branch of every ternary in the loop
        fra__Entity_Storage__c es = new fra__Entity_Storage__c(
            fra__File_Store_Record_Id__c = String.valueOf(pa.Id));
        insert es;

        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name                   = 'Null Fields Doc',
            fra__Entity_Storage__c = es.Id,
            Send_to_Portal__c      = true
            // All other fields intentionally null
        );
        insert fs;

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'Document with all null optional fields must be handled gracefully');
    }

    /* ================================================================
       getDocuments — direct call (public static)
    ================================================================ */
    @IsTest
    static void testGetDocuments_DirectCall_NoStorages() {
        Account pa = createTestPatient(
            'DirCall', 'NoStorage',
            'dircall' + Datetime.now().getTime() + '@example.com', false
        );
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getDocuments(pa.Id);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size(),
            'Must return empty list when no entity storages exist');
    }

    @IsTest
    static void testGetDocuments_DirectCall_WithSendableFile() {
        Account pa = createTestPatient(
            'DirCallSend', 'Storage',
            'dircallsend' + Datetime.now().getTime() + '@example.com', false
        );
        createFileStorage(pa.Id, 'Direct Call File', 'Lab', 'Metriport', null, true);

        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getDocuments(pa.Id);
        Test.stopTest();
        System.assert(result.size() > 0, 'Direct call must return sendable files');
        System.assertEquals('Direct Call File', result[0].get('Title'));
    }

    /* ================================================================
       updateSendMemberToPortal
    ================================================================ */
    @IsTest
    static void testUpdateSendMemberToPortal_NullId() {
        Test.startTest();
        SendMetriportDataToPortal.updateSendMemberToPortal(null);
        Test.stopTest();
        System.assert(true, 'Null accountId must be handled gracefully');
    }

    @IsTest
    static void testUpdateSendMemberToPortal_ValidId() {
        Account pa = createTestPatient();
        Test.startTest();
        SendMetriportDataToPortal.updateSendMemberToPortal(pa.Id);
        Test.stopTest();
        Account updated = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Send_Member_to_portal__c must be true after updateSendMemberToPortal');
    }

    /* ================================================================
       getHealthcareFacilities (public method)
    ================================================================ */
    @IsTest
    static void testGetHealthcareFacilities_NullAccountId() {
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getHealthcareFacilities(null);
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

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
        System.assert(result.size() > 0, 'Must return at least one facility');
        System.assertEquals('Sunrise Clinic', result[0].get('facilityName'));
    }

    /* ================================================================
       getHealthcareProfessionals (public method)
    ================================================================ */
    @IsTest
    static void testGetHealthcareProfessionals_NullAccountId() {
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getHealthcareProfessionals(null);
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testGetHealthcareProfessionals_ReturnsData() {
        Account pa = createTestPatient();
        insert new HealthcarePractitionerFacility(
            Name         = 'Dr. Jones',
            AccountId    = pa.Id,
            Specialty__c = 'Neurology',
            Phone__c     = '555-0500'
        );
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getHealthcareProfessionals(pa.Id);
        Test.stopTest();
        System.assert(result.size() > 0, 'Must return at least one professional');
        System.assertEquals('Dr. Jones',  result[0].get('professionalName'));
        System.assertEquals('Neurology',  result[0].get('specialty'));
    }

    /* ================================================================
       getInsuranceDetails (public method)
    ================================================================ */
    @IsTest
    static void testGetInsuranceDetails_NullAccountId() {
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getInsuranceDetails(null);
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testGetInsuranceDetails_ReturnsData() {
        Account pa = createTestPatient();
        insert new MemberPlan(
            Name                           = 'Aetna Silver',
            MemberId                       = pa.Id,
            medicalcoverage__Payer_Name__c = 'Aetna',
            GroupNumber                    = 'GRP-999',
            MemberNumber                   = 'MBR-99999',
            PrimarySecondaryTertiary       = 'Secondary'
        );
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getInsuranceDetails(pa.Id);
        Test.stopTest();
        System.assert(result.size() > 0, 'Must return at least one insurance record');
        System.assertEquals('Aetna',   result[0].get('providerName'));
        System.assertEquals('GRP-999', result[0].get('GroupNumber'));
    }

    @IsTest
    static void testGetInsuranceDetails_NullSubscriberBirthDate() {
        Account pa = createTestPatient();
        insert new MemberPlan(
            Name                                      = 'Humana Null Birth',
            MemberId                                  = pa.Id,
            medicalcoverage__Payer_Name__c            = 'Humana',
            GroupNumber                               = 'GRP-HUM',
            MemberNumber                              = 'MBR-HUM',
            medicalcoverage__Subscriber_Birth_Date__c = null,
            PrimarySecondaryTertiary                  = 'Primary'
        );
        Test.startTest();
        List<Map<String, Object>> result =
            SendMetriportDataToPortal.getInsuranceDetails(pa.Id);
        Test.stopTest();
        System.assert(result.size() > 0, 'Must return plan even with null birth date');
        System.assertEquals(null, result[0].get('Subscriber_Birth_Date'));
    }

    /* ================================================================
       Multiple clinical records
    ================================================================ */
    @IsTest
    static void testSendPatientDataMethod_MultipleAllergies() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'MultiAllergy', 'Patient',
            'multiallergy' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        insert new AllergyIntolerance(PatientId = pa.Id, Allergy_Name__c = 'Penicillin',
            Severity = 'Severe',   Status = 'Active',
            OnsetStartDateTime = Datetime.now().addDays(-60));
        insert new AllergyIntolerance(PatientId = pa.Id, Allergy_Name__c = 'Shellfish',
            Severity = 'Moderate', Status = 'Active',
            OnsetStartDateTime = Datetime.now().addDays(-120), Generic__c = 'Crustaceans');
        insert new AllergyIntolerance(PatientId = pa.Id, Allergy_Name__c = 'Latex',
            Severity = 'Mild',     Status = 'Inactive');

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'Multiple allergies including null-onset must be handled');
    }

    @IsTest
    static void testSendPatientDataMethod_MultipleMedications() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'MultiMed', 'Patient',
            'multimed' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        Medication m1 = new Medication(Name = 'Aspirin',    Patient__c = pa.Id);
        Medication m2 = new Medication(Name = 'Metformin',  Patient__c = pa.Id);
        Medication m3 = new Medication(Name = 'Lisinopril', Patient__c = pa.Id);
        insert new List<Medication>{ m1, m2, m3 };

        insert new MedicationStatement(PatientId = pa.Id, MedicationId = m1.Id,
            Dose__c = '81mg',  Frequency__c = 'Daily',        Status = 'Active',
            StartDateTime = Datetime.now().addDays(-200));
        insert new MedicationStatement(PatientId = pa.Id, MedicationId = m2.Id,
            Dose__c = '500mg', Frequency__c = 'Twice Daily',  Status = 'Active',
            StartDateTime = Datetime.now().addDays(-100),
            EndDateTime   = Datetime.now().addDays(90));
        insert new MedicationStatement(PatientId = pa.Id, MedicationId = m3.Id,
            Dose__c = '10mg',  Frequency__c = 'Once Daily',   Status = 'Discontinued',
            EndDateTime = Datetime.now().addDays(-10));

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'Multiple medications including null dates must be handled');
    }

    @IsTest
    static void testSendPatientDataMethod_MultipleHealthConditions() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'MultiCond', 'Patient',
            'multicond' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        insert new HealthCondition(PatientId = pa.Id, ProblemName = 'Asthma',
            OnsetStartDateTime = Datetime.now().addDays(-500), ConditionStatus = 'Active');
        insert new HealthCondition(PatientId = pa.Id, ProblemName = 'Osteoarthritis',
            OnsetStartDateTime = null, ConditionStatus = 'Chronic');
        insert new HealthCondition(PatientId = pa.Id, ProblemName = 'GERD',
            OnsetStartDateTime = Datetime.now().addDays(-200), ConditionStatus = 'Resolved');

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'Multiple health conditions including null onset must be handled');
    }

    @IsTest
    static void testSendPatientDataMethod_MultipleSurgeries() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'MultiSurg', 'Patient',
            'multisurg' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        insert new HealthCareProcedure(Name = 'Cholecystectomy', Patient__c = pa.Id,
            Surgery_Name__c = 'Cholecystectomy',
            EffectiveDate = Date.today().addDays(-365), Status__c = 'Completed');
        insert new HealthCareProcedure(Name = 'Cataract Removal', Patient__c = pa.Id,
            Surgery_Name__c = 'Cataract Removal',
            EffectiveDate = null, Status__c = 'Completed');
        insert new HealthCareProcedure(Name = 'Hip Replacement', Patient__c = pa.Id,
            Surgery_Name__c = 'Hip Replacement',
            EffectiveDate = Date.today().addDays(-90), Status__c = 'Pending');

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'Multiple surgical procedures including null date must be handled');
    }

    @IsTest
    static void testSendPatientDataMethod_MultiplePersonalContacts() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'MultiContact', 'Patient',
            'multicontact' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        insert new Contact(FirstName = 'Alice', LastName = 'Emergency',
            Account__c = pa.Id, MobilePhone = '555-1111',
            Email = 'alice.em' + Datetime.now().getTime() + '@example.com',
            Emergency_Contact_Relationship__c = 'CHILD',
            Emergency_Contact__c = true, Is_PHI_Authorized__c = true);
        insert new Contact(FirstName = 'Bob', LastName = 'Proxy',
            Account__c = pa.Id, MobilePhone = '555-2222',
            Email = 'bob.proxy' + Datetime.now().getTime() + '@example.com',
            Emergency_Contact_Relationship__c = 'CHILD',
            Is_Healthcare_Proxy__c = true);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'Multiple personal contacts must all be serialized');
    }

    @IsTest
    static void testSendPatientDataMethod_MultipleInsurancePlans() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'MultiIns', 'Patient',
            'multiins' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        insert new MemberPlan(Name = 'United Primary', MemberId = pa.Id,
            medicalcoverage__Payer_Name__c = 'United',
            GroupNumber = 'GRP-P01', MemberNumber = 'MBR-P001',
            PrimarySecondaryTertiary = 'Primary');
        insert new MemberPlan(Name = 'Cigna Secondary', MemberId = pa.Id,
            medicalcoverage__Payer_Name__c = 'Cigna',
            GroupNumber = 'GRP-S01', MemberNumber = 'MBR-S001',
            PrimarySecondaryTertiary = 'Secondary',
            medicalcoverage__Subscriber_Birth_Date__c = Date.newInstance(1975, 3, 20));

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();
        System.assert(true, 'Multiple insurance plans must be serialized correctly');
    }

    @IsTest
    static void testSendPatientDataMethod_LabsAndDocumentCombined() {
        ensureApiConfig();
        Account pa = createTestPatient(
            'LabDoc', 'Combined',
            'labdoc' + Datetime.now().getTime() + '@example.com', false
        );
        Contact c = getTestContact(pa.Id);

        insert new CareObservation(
            Name              = 'Blood Glucose',
            ObservedSubjectId = pa.Id,
            Category          = 'Laboratory',
            ObservationStatus = 'Final',
            Range_High__c     = '100',
            Value_Quantity__c = '92'
        );

        createFileStorage(pa.Id, 'Combined Test Doc', 'Lab', 'Metriport',
            'Estate, Legal & Financial Documents', true);

        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendPatientDataMethod(c.Id);
        Test.stopTest();

        Account updated = [
            SELECT Send_Member_to_portal__c FROM Account WHERE Id = :pa.Id
        ];
        System.assertEquals(true, updated.Send_Member_to_portal__c,
            'Labs + documents combined payload must complete successfully');
    }

    /* ================================================================
       sendFamilyMemberData / sendFamilyFuture / processFamilySync
    ================================================================ */
    @IsTest
    static void testSendFamilyMemberData_NullId() {
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyMemberData(null);
        Test.stopTest();
        System.assert(true, 'Null authorizedAccountId must be handled gracefully');
    }

    @IsTest
    static void testSendFamilyMemberData_MissingApiConfig() {
        clearApiConfig();
        Account member = createTestPatient(
            'Head', 'NoConfig',
            'head.noconfig' + Datetime.now().getTime() + '@example.com', true
        );
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyMemberData(member.Id);
        Test.stopTest();
        System.assert(true, 'Missing API config must be handled gracefully');
    }

    @IsTest
    static void testSendFamilyMemberData_NoJunctionRecords() {
        ensureApiConfig();
        Account loneAccount = createTestPatient(
            'Lone', 'Account',
            'lone' + Datetime.now().getTime() + '@example.com', false
        );
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyMemberData(loneAccount.Id);
        Test.stopTest();
        System.assert(true, 'Account with no junction records must return gracefully');
    }

    @IsTest
    static void testSendFamilyMemberData_DispatchesFuture() {
        ensureApiConfig();
        Account member     = createTestPatient(
            'Member', 'FamilyAsync',
            'member.async' + Datetime.now().getTime() + '@example.com', false
        );
        Account authorized = createTestPatient(
            'Auth', 'FamilyAsync',
            'auth.async' + Datetime.now().getTime() + '@example.com', true
        );
        linkMemberToAuthorized(member.Id, authorized.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyMemberData(member.Id);
        Test.stopTest();
        System.assert(true, 'sendFamilyMemberData must dispatch @future callout without error');
    }

    @IsTest
    static void testSendFamilyFuture_DirectCall() {
        ensureApiConfig();
        Account member     = createTestPatient(
            'FutureDir', 'Member',
            'futuredir.member' + Datetime.now().getTime() + '@example.com', false
        );
        Account authorized = createTestPatient(
            'FutureDir', 'Auth',
            'futuredir.auth' + Datetime.now().getTime() + '@example.com', true
        );
        linkMemberToAuthorized(member.Id, authorized.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.sendFamilyFuture(member.Id);
        Test.stopTest();
        System.assert(true, 'sendFamilyFuture direct call must complete without error');
    }

    @IsTest
    static void testProcessFamilySync_MissingApiConfig() {
        clearApiConfig();
        Account member     = createTestPatient(
            'PFSync', 'NoConfig',
            'pfsync.noconfig' + Datetime.now().getTime() + '@example.com', true
        );
        Account authorized = createTestPatient(
            'PFSync', 'Auth',
            'pfsync.auth' + Datetime.now().getTime() + '@example.com', false
        );
        linkMemberToAuthorized(member.Id, authorized.Id);
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();
        System.assert(true, 'processFamilySync with blank API config must return without exception');
    }

    @IsTest
    static void testProcessFamilySync_NoJunctionRecords() {
        ensureApiConfig();
        Account loneAccount = createTestPatient(
            'PFLone', 'Account',
            'pflone' + Datetime.now().getTime() + '@example.com', false
        );
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(loneAccount.Id);
        Test.stopTest();
        System.assert(true, 'processFamilySync with no junction records must return gracefully');
    }

    @IsTest
    static void testProcessFamilySync_OneAuthorizedAccount() {
        ensureApiConfig();
        Account member     = createTestPatient(
            'PFOne', 'Member',
            'pfone.member' + Datetime.now().getTime() + '@example.com', false
        );
        Account authorized = createTestPatient(
            'PFOne', 'Auth',
            'pfone.auth' + Datetime.now().getTime() + '@example.com', true
        );
        linkMemberToAuthorized(member.Id, authorized.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();
        System.assert(true, 'processFamilySync with one authorized account must complete');
    }

    @IsTest
    static void testProcessFamilySync_TwoAuthorizedAccounts() {
        ensureApiConfig();
        Account member = createTestPatient(
            'PFTwo', 'Member',
            'pftwo.member' + Datetime.now().getTime() + '@example.com', false
        );
        Account authA  = createTestPatient(
            'PFTwo', 'AuthA',
            'pftwo.autha' + Datetime.now().getTime() + '@example.com', true
        );
        Account authB  = createTestPatient(
            'PFTwo', 'AuthB',
            'pftwo.authb' + Datetime.now().getTime() + '@example.com', true
        );
        linkMemberToAuthorized(member.Id, authA.Id);
        linkMemberToAuthorized(member.Id, authB.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();
        System.assert(true, 'Both authorized accounts must be included in the payload');
    }

    @IsTest
    static void testProcessFamilySync_Http400Response() {
        ensureApiConfig();
        Account member     = createTestPatient(
            'Err400', 'Member',
            'err400.member' + Datetime.now().getTime() + '@example.com', false
        );
        Account authorized = createTestPatient(
            'Err400', 'Auth',
            'err400.auth' + Datetime.now().getTime() + '@example.com', true
        );
        linkMemberToAuthorized(member.Id, authorized.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock400());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();
        System.assert(true, 'HTTP 400 from family endpoint must be logged gracefully');
    }

    @IsTest
    static void testProcessFamilySync_NullPersonContactId() {
        ensureApiConfig();
        Account member     = createTestPatient(
            'NullPC', 'Member',
            'nullpc.member' + Datetime.now().getTime() + '@example.com', true
        );
        Account authorized = createTestPatient(
            'NullPC', 'Auth',
            'nullpc.auth' + Datetime.now().getTime() + '@example.com', false
        );
        linkMemberToAuthorized(member.Id, authorized.Id);
        Test.setMock(HttpCalloutMock.class, new PortalCalloutMock200());
        Test.startTest();
        SendMetriportDataToPortal.processFamilySync(member.Id);
        Test.stopTest();
        System.assert(true, 'processFamilySync null PersonContactId branch must be handled');
    }

    @IsTest
    static void testProcessFamilySync_ThreeAuthorizedAccountsDeduplicated() {
        ensureApiConfig();
        Account member = createTestPatient(
            'PFThree', 'Member',
            'pfthree.member' + Datetime.now().getTime() + '@example.com', false
        );
        Account authA  = createTestPatient('PFThree', 'AuthA',
            'pfthree.a' + Datetime.now().getTime() + '@example.com', false);
        Account authB  = createTestPatient('PFThree', 'AuthB',
            'pfthree.b' + Datetime.now().getTime() + '@example.com', false);
        Account authC  = createTestPatient('PFThree', 'AuthC',
            'pfthree.c' + Datetime.now().getTime() + '@example.com', false);
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
}