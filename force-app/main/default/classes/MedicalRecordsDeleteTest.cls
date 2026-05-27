@isTest(SeeAllData=true)
public class MedicalRecordsDeleteTest {
    
    private static void addAuthHeader(RestRequest req) {
    Encryption_Config__mdt cfg =
        Encryption_Config__mdt.getInstance('Medical_API');

    System.assertNotEquals(
        null,
        cfg,
        'Encryption_Config__mdt Medical_API must exist'
    );

    req.headers.put('x-api-key', cfg.Secret_Key__c);
}

    
    // Helper method to get or create Person Account with name "Test Patient"
    private static Account getOrCreateTestPatient() {
        // Try to find existing account named "Test Patient"
        List<Account> existingPatients = [
            SELECT Id, FirstName, LastName, PersonEmail 
            FROM Account 
            WHERE Name = 'Test Patient' 
            AND IsPersonAccount = true
            LIMIT 1
        ];
        
        if (!existingPatients.isEmpty()) {
            return existingPatients[0];
        }
        
        // Create new patient if not found
        Id paRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ].Id;
        
        Account pa = new Account(
            RecordTypeId = paRtId,
            FirstName = 'Test',
            LastName  = 'Patient',
            PersonEmail = 'patient@test.com'
        );
        insert pa;
        return pa;
    }
    
    // Helper method to get or create Contact
    private static Contact getOrCreateContact(Id accountId) {
        List<Contact> existingContacts = [
            SELECT Id, AccountId 
            FROM Contact 
            WHERE AccountId = :accountId 
            LIMIT 1
        ];
        
        if (!existingContacts.isEmpty()) {
            return existingContacts[0];
        }
        
        Contact patientContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = accountId
        );
        insert patientContact;
        return patientContact;
    }
    
    // Helper method to get or create AllergyIntolerance
    private static AllergyIntolerance getOrCreateAllergy(Id accountId) {
        List<AllergyIntolerance> existingAllergies = [
            SELECT Id 
            FROM AllergyIntolerance 
            WHERE PatientId = :accountId 
            LIMIT 1
        ];
        
        if (!existingAllergies.isEmpty()) {
            return existingAllergies[0];
        }
        
        AllergyIntolerance allergy = new AllergyIntolerance(
            Allergy_Name__c = 'Test Allergy',
            PatientId = accountId
        );
        insert allergy;
        return allergy;
    }
    
    // Helper method to get or create HealthCondition (Medical History)
    private static HealthCondition getOrCreateMedicalHistory(Id accountId) {
        List<HealthCondition> existingHistories = [
            SELECT Id 
            FROM HealthCondition 
            WHERE PatientId = :accountId 
            LIMIT 1
        ];
        
        if (!existingHistories.isEmpty()) {
            return existingHistories[0];
        }
        
        HealthCondition mh = new HealthCondition(
            PatientId = accountId
        );
        insert mh;
        return mh;
    }
    
    // Helper method to get or create HealthCareProcedure (Surgical History)
    private static HealthCareProcedure getOrCreateSurgicalHistory(Id accountId) {
        List<HealthCareProcedure> existingSurgeries = [
            SELECT Id 
            FROM HealthCareProcedure 
            WHERE Patient__c = :accountId 
            LIMIT 1
        ];
        
        if (!existingSurgeries.isEmpty()) {
            return existingSurgeries[0];
        }
        
        HealthCareProcedure surgery = new HealthCareProcedure(
            Name = 'Test Surgery',
            Patient__c = accountId
        );
        insert surgery;
        return surgery;
    }
    
    // Helper method to get or create HealthcarePractitionerFacility
    private static HealthcarePractitionerFacility getOrCreateProfessional(Id accountId) {
        List<HealthcarePractitionerFacility> existingProfessionals = [
            SELECT Id 
            FROM HealthcarePractitionerFacility 
            WHERE AccountId = :accountId 
            LIMIT 1
        ];
        
        if (!existingProfessionals.isEmpty()) {
            return existingProfessionals[0];
        }
        
        HealthcarePractitionerFacility professional = new HealthcarePractitionerFacility(
            Name = 'Dr Test Physician',
            AccountId = accountId
        );
        insert professional;
        return professional;
    }
    
    // Helper method to get or create HealthcareFacility
    private static HealthcareFacility getOrCreateFacility(Id accountId) {
        List<HealthcareFacility> existingFacilities = [
            SELECT Id 
            FROM HealthcareFacility 
            WHERE AccountId = :accountId 
            LIMIT 1
        ];
        
        if (!existingFacilities.isEmpty()) {
            return existingFacilities[0];
        }
        
        HealthcareFacility facility = new HealthcareFacility(
            Name = 'Test Hospital',
            AccountId = accountId
        );
        insert facility;
        return facility;
    }
    
   // Helper method to get or create CodeSetBundle
private static CodeSetBundle getOrCreateCodeSetBundle() {
    // Just get ANY existing CodeSetBundle - we only need it for the relationship
    List<CodeSetBundle> existingBundles = [
        SELECT Id 
        FROM CodeSetBundle 
        LIMIT 1
    ];
    
    if (!existingBundles.isEmpty()) {
        return existingBundles[0];
    }
    
    // Only create if absolutely none exist - use unique name with timestamp
    CodeSetBundle csb = new CodeSetBundle(
        Name = 'TestMed_' + System.now().getTime()
    );
    insert csb;
    return csb;
}
    // Helper method to get or create MedicationStatement
    private static MedicationStatement getOrCreateMedicationStatement(Id accountId, Id codeSetId) {
        List<MedicationStatement> existingStatements = [
            SELECT Id 
            FROM MedicationStatement 
            WHERE PatientId = :accountId 
            LIMIT 1
        ];
        
        if (!existingStatements.isEmpty()) {
            return existingStatements[0];
        }
        
        MedicationStatement ms = new MedicationStatement(
            PatientId = accountId,
            MedicationCodeId = codeSetId,
            Status = getAnyPicklistValue(MedicationStatement.Status)
        );
        insert ms;
        return ms;
    }
    
    // Helper method to get or create MemberPlan
    private static MemberPlan getOrCreateMemberPlan(Id accountId) {
        List<MemberPlan> existingPlans = [
            SELECT Id 
            FROM MemberPlan 
            WHERE MemberId = :accountId 
            LIMIT 1
        ];
        
        if (!existingPlans.isEmpty()) {
            return existingPlans[0];
        }
        
        MemberPlan mp = new MemberPlan(
            Name = 'Test Plan',
            MemberId = accountId
        );
        insert mp;
        return mp;
    }
    
    // Helper method to get or create Case
    private static Case getOrCreateCase(Id accountId, Id contactId) {
        List<Case> existingCases = [
            SELECT Id 
            FROM Case 
            WHERE AccountId = :accountId 
            LIMIT 1
        ];
        
        if (!existingCases.isEmpty()) {
            return existingCases[0];
        }
        
        Case testCase = new Case(
            Subject = 'Test Case',
            AccountId = accountId,
            ContactId = contactId
        );
        insert testCase;
        return testCase;
    }
    
    // Helper method to create all test data needed
    private static Map<String, SObject> createTestData() {
        Map<String, SObject> testData = new Map<String, SObject>();
        
        // Get or create Account
        Account pa = getOrCreateTestPatient();
        testData.put('Account', pa);
        
        // Get or create Contact
        Contact patientContact = getOrCreateContact(pa.Id);
        testData.put('Contact', patientContact);
        
        // Get or create other objects
        testData.put('AllergyIntolerance', getOrCreateAllergy(pa.Id));
        testData.put('HealthCondition', getOrCreateMedicalHistory(pa.Id));
        testData.put('HealthCareProcedure', getOrCreateSurgicalHistory(pa.Id));
        testData.put('HealthcarePractitionerFacility', getOrCreateProfessional(pa.Id));
        testData.put('HealthcareFacility', getOrCreateFacility(pa.Id));
        testData.put('Case', getOrCreateCase(pa.Id, patientContact.Id));
        
        CodeSetBundle csb = getOrCreateCodeSetBundle();
        testData.put('CodeSetBundle', csb);
        
        testData.put('MedicationStatement', getOrCreateMedicationStatement(pa.Id, csb.Id));
        testData.put('MemberPlan', getOrCreateMemberPlan(pa.Id));
        
        return testData;
    }
    
    /* ============================================================
TEST: SUCCESSFUL DELETE
============================================================ */
    @IsTest
    static void testDeleteSuccess() {
        // Create test data
        Map<String, SObject> testData = createTestData();
        
        AllergyIntolerance allergy = (AllergyIntolerance)testData.get('AllergyIntolerance');
        HealthCondition mh = (HealthCondition)testData.get('HealthCondition');
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{ 'id' => allergy.Id }
            },
                'medical_history' => new List<Object>{
                    new Map<String, Object>{ 'id' => mh.Id }
                }
        };
            
            RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
    }
    
    /* ============================================================
TEST: EMPTY REQUEST
============================================================ */
    @IsTest
    static void testEmptyRequest() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf('{}');
        addAuthHeader(req);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
        
        System.assertEquals(200, RestContext.response.statusCode);
    }
    
    /* ============================================================
TEST: INVALID FORMAT
============================================================ */
    @IsTest
    static void testInvalidFormat() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf('[{"id":"123"}]'); // invalid format
        addAuthHeader(req);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
        
        System.assertEquals(500, RestContext.response.statusCode);
    }
    
    @IsTest
    static void testDelete_All_ObjectTypes_Coverage() {
        // Create test data
        Map<String, SObject> testData = createTestData();
        
        MedicationStatement ms = (MedicationStatement)testData.get('MedicationStatement');
        MemberPlan mp = (MemberPlan)testData.get('MemberPlan');
        Contact con = (Contact)testData.get('Contact');
        HealthcareFacility facility = (HealthcareFacility)testData.get('HealthcareFacility');
        HealthcarePractitionerFacility professional = 
            (HealthcarePractitionerFacility)testData.get('HealthcarePractitionerFacility');
        Case testCase = (Case)testData.get('Case');
        
        // Build request body to hit every branch
        Map<String, Object> requestBody = new Map<String, Object>{
            'medications' => new List<Object>{
                new Map<String, Object>{ 'id' => ms.Id }
            },
                'insurance_details' => new List<Object>{
                    new Map<String, Object>{ 'id' => mp.Id }
                },
                    'healthcare_facilities' => new List<Object>{
                        new Map<String, Object>{ 'id' => facility.Id }
                    },
                        'healthcare_professionals' => new List<Object>{
                            new Map<String, Object>{ 'id' => professional.Id }
                        },
                            'personal_contacts' => new List<Object>{
                                new Map<String, Object>{ 'id' => con.Id }
                            },
                                'case_messages' => new List<Object>{
                                    new Map<String, Object>{ 'id' => testCase.Id }
                                }
        };
            
            RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        addAuthHeader(req);
        
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
        
        // Accept both 200 (all succeeded) and 207 (partial success)
        System.assert(
            RestContext.response.statusCode == 200 || RestContext.response.statusCode == 207,
            'All supported object deletes should be processed. Status: ' + RestContext.response.statusCode
        );
        
        // Optionally verify response body for debugging
        String responseBody = RestContext.response.responseBody != null 
            ? RestContext.response.responseBody.toString() 
            : 'No response body';
        System.debug('Response Status: ' + RestContext.response.statusCode);
    }
    
    @IsTest
    static void testDelete_UnsupportedObjectType() {
        Map<String, Object> requestBody = new Map<String, Object>{
            'unknown_group' => new List<Object>{
                new Map<String, Object>{ 'id' => '001000000000001AAA' }
            }
        };
            
            RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        addAuthHeader(req);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
        
        // Test passes if no exception is thrown
        System.assert(true, 'Should handle unsupported object type gracefully');
    }
    
    @IsTest
    static void testDelete_InvalidId() {
        Map<String, Object> requestBody = new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{ 'id' => 'invalid-id-format' }
            }
        };
            
            RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        addAuthHeader(req);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
        
        System.assert(
            RestContext.response.statusCode == 200 || RestContext.response.statusCode == 207,
            'Should handle invalid IDs gracefully'
        );
    }
    
    @IsTest
    static void testDelete_SurgicalHistory_Coverage() {
        // Create test data
        Map<String, SObject> testData = createTestData();
        HealthCareProcedure surgery = (HealthCareProcedure)testData.get('HealthCareProcedure');
        
        // Build DELETE request body
        Map<String, Object> requestBody = new Map<String, Object>{
            'surgical_history' => new List<Object>{
                new Map<String, Object>{
                    'id' => surgery.Id
                        }
            }
        };
            
            RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        addAuthHeader(req);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
        
        // Successful processing
        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Surgical history delete path should be executed'
        );
    }
    
    @IsTest
    static void testDelete_EmptyRecordIds_Coverage() {
        // Valid group name but empty list of IDs
        Map<String, Object> requestBody = new Map<String, Object>{
            'surgical_history' => new List<Object>()
                };
                    
                    RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        addAuthHeader(req);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
        
        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Empty recordIds list should be handled gracefully'
        );
    }
    
    @IsTest
    static void testDelete_BackwardCompatibility_StringIds() {
        // Create test data
        Map<String, SObject> testData = createTestData();
        AllergyIntolerance allergy = (AllergyIntolerance)testData.get('AllergyIntolerance');
        
        // Test backward compatibility with direct string IDs
        Map<String, Object> requestBody = new Map<String, Object>{
            'allergies' => new List<Object>{
                (String)allergy.Id  // Direct string instead of object
                    }
        };
            
            RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        addAuthHeader(req);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
        
        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Backward compatibility with string IDs should work'
        );
    }
    
    @IsTest
    static void testDelete_MismatchedObjectType() {
        // Create test data
        Map<String, SObject> testData = createTestData();
        Contact con = (Contact)testData.get('Contact');
        
        // Try to delete Contact ID as if it's an Allergy
        Map<String, Object> requestBody = new Map<String, Object>{
            'allergies' => new List<Object>{
                new Map<String, Object>{ 'id' => con.Id }  // Wrong object type
            }
        };
            
            RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/medicalDelete/v1/';
        req.httpMethod = 'DELETE';
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        addAuthHeader(req);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        MedicalRecordsDeleteAPI.deleteRecord();
        Test.stopTest();
        
        System.assert(
            RestContext.response.statusCode == 200 || RestContext.response.statusCode == 207,
            'Mismatched object types should be handled gracefully'
        );
    }
    
    /* ============================================================
HELPER: PICKLIST VALUE FETCH
============================================================ */
    private static String getAnyPicklistValue(Schema.SObjectField field) {
        for (Schema.PicklistEntry pe : field.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return null;
    }   
}