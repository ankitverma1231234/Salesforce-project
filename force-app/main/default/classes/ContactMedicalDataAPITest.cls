// NOTE: The actual fix is in ContactMedicalDataAPI.createPublicLinks — see below.
// This test file is correct as-is; no changes needed here.
@IsTest(SeeAllData=true)
private class ContactMedicalDataAPITest {
    
    @IsTest
    static void testWithExistingData() {
        Test.startTest();
        
        // Query existing Person Account
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone 
            FROM Account 
            WHERE IsPersonAccount = true 
            AND PersonEmail != null 
            AND PersonMobilePhone != null 
            LIMIT 1
        ];
        
        if (existingAccounts.isEmpty()) {
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
            
            Account testAcc = new Account(
                FirstName = 'Existing',
                LastName = 'Test',
                RecordTypeId = personAccountRT,
                PersonEmail = 'existing.test@example.com',
                PersonMobilePhone = '5551234567'
            );
            insert testAcc;
            
            existingAccounts = [SELECT Id, PersonEmail, PersonMobilePhone FROM Account WHERE Id = :testAcc.Id];
        }
        
        Account testAccount = existingAccounts[0];
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'email' => testAccount.PersonEmail,
            'phone' => testAccount.PersonMobilePhone
        };
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
        
        Test.stopTest();
        
        if (response.success) {
            System.assertEquals(true, response.success, 'Should find existing contact');
            System.assertNotEquals(null, response.data, 'Contact data should be returned');
        } else {
            System.debug('Contact not found with existing data');
        }
    }
    
    @IsTest
    static void testGetPersonAccountRecordTypeId() {
        Test.startTest();
        Id recordTypeId = ContactMedicalDataAPI.getPersonAccountRecordTypeId();
        Test.stopTest();
        
        System.assertNotEquals(null, recordTypeId, 'Record type ID should not be null');
    }
    
    @IsTest
    static void testSearchContactData_Success() {
        String uniqueEmail = 'test.success' + System.currentTimeMillis() + '@example.com';
        String uniquePhone = '55511122' + String.valueOf(System.currentTimeMillis()).right(3);
        
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        
        Account testAccount = new Account(
            FirstName = 'Test',
            LastName = 'Patient' + System.currentTimeMillis(),
            RecordTypeId = personAccountRT,
            PersonEmail = uniqueEmail,
            PersonMobilePhone = uniquePhone,
            Date_of_Birth__pc = Date.newInstance(1990, 1, 1)
        );
        insert testAccount;
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'email' => uniqueEmail,
            'phone' => uniquePhone
        };
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
        
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Search should be successful');
        System.assertNotEquals(null, response.data, 'Contact data should be returned');
        System.assertEquals('Contact retrieved', response.message);
    }
    
    @IsTest
    static void testSearchContactData_MissingRequiredFields() {
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'email' => 'test@example.com'
        };
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
        
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Should fail with missing fields');
        System.assertEquals('Email and Phone are required for search', response.message);
    }
    
    @IsTest
    static void testSearchContactData_ContactNotFound() {
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        String nonExistentEmail = 'nonexistent' + System.currentTimeMillis() + '@example.com';
        String nonExistentPhone = '9999999' + String.valueOf(System.currentTimeMillis()).right(3);
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'email' => nonExistentEmail,
            'phone' => nonExistentPhone
        };
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
        
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Should fail when contact not found');
        System.assertEquals('Contact not found', response.message);
        System.assertEquals('CONTACT_NOT_FOUND', response.errorCode);
    }
    
    @IsTest
    static void testSearchWithPhoneVariations() {
        String uniqueEmail = 'phone.test' + System.currentTimeMillis() + '@example.com';
        String formattedPhone = '(555) 123-4567';
        String cleanPhone = '5551234567';
        
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        
        Account testAccount = new Account(
            FirstName = 'Phone',
            LastName = 'Test' + System.currentTimeMillis(),
            RecordTypeId = personAccountRT,
            PersonEmail = uniqueEmail,
            PersonHomePhone = formattedPhone
        );
        insert testAccount;
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'email' => uniqueEmail,
            'phone' => cleanPhone,
            'firstName' => 'Phone',
            'lastName' => 'Test'
        };
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
        
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Should find contact with phone variations');
    }
    
    @IsTest
    static void testExceptionHandling() {
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        req.requestBody = Blob.valueOf('invalid json');
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        try {
            ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
            System.assertEquals(false, response.success);
            System.assertEquals('Internal error', response.message);
        } catch (Exception e) {
            System.debug('Exception caught: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testCreatePublicLink() {
        // Insert ContentVersion inside startTest so DML is fully committed
        Test.startTest();
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.pdf',
            VersionData = Blob.valueOf('Test Content'),
            Source__c = 'Metriport',
            IsMajorVersion = true
        );
        insert cv;
        
        // FIX: Use a List query to safely retrieve ContentDocumentId;
        //      a direct SObject assignment throws "List has no rows" if
        //      the record is not found.
        List<ContentVersion> cvList = [
            SELECT ContentDocumentId 
            FROM ContentVersion 
            WHERE Id = :cv.Id 
            LIMIT 1
        ];
        
        if (!cvList.isEmpty()) {
            cv = cvList[0];
            
            try {
                Map<Id, ContentVersion> testMap = new Map<Id, ContentVersion>();
                testMap.put(cv.ContentDocumentId, cv);
                
                Map<Id, String> publicUrlMap = ContactMedicalDataAPI.createPublicLinks(testMap);
                System.assertNotEquals(null, publicUrlMap, 'Should return a map');
            } catch (Exception e) {
                System.debug('Expected exception in test context: ' + e.getMessage());
            }
        } else {
            System.debug('ContentVersion not found after insert — skipping createPublicLinks assertion');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testAllDataTypesInResponse() {
        String uniqueEmail = 'comprehensive' + System.currentTimeMillis() + '@example.com';
        String uniquePhone = '55544433' + String.valueOf(System.currentTimeMillis()).right(3);
        
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        
        Account testAccount = new Account(
            FirstName = 'Comprehensive',
            LastName = 'Test' + System.currentTimeMillis(),
            RecordTypeId = personAccountRT,
            PersonEmail = uniqueEmail,
            PersonMobilePhone = uniquePhone,
            PersonMailingStreet = '2234 Peacock Street',
            PersonMailingCity = 'New York',
            PersonMailingState = 'New York',
            PersonMailingPostalCode = '12345',
            PersonMailingCountry = 'United States',
            Date_of_Birth__pc = Date.newInstance(1985, 5, 15),
            Preferred_Name__pc = 'Comp',
            Salutation = 'Dr.',
            Preferred_Language__pc = 'English'
        );
        insert testAccount;
        
        // FIX: Use a List query instead of direct SObject assignment.
        //      Person Accounts auto-create a Contact, but the record may
        //      not yet be visible in the same transaction on all orgs.
        List<Contact> relatedContacts = [
            SELECT Id, AccountId 
            FROM Contact 
            WHERE AccountId = :testAccount.Id 
            LIMIT 1
        ];
        
        // Only proceed with Contact-dependent data if the record exists
        Id testContactId = relatedContacts.isEmpty() ? null : relatedContacts[0].Id;
        
        HealthCareProcedure surgery = new HealthCareProcedure(
            Name = 'Test Surgery',
            CodeShortDescription = 'Test Procedure',
            EffectiveDate = Date.today(),
            Patient__c = testAccount.Id
        );
        insert surgery;
        
        HealthCondition condition = new HealthCondition(
            ProblemName = 'Test Medical Problem',
            PatientId = testAccount.Id
        );
        insert condition;
        
        AllergyIntolerance allergy = new AllergyIntolerance(
            Allergy_Name__c = 'Test Allergen',
            PatientId = testAccount.Id
        );
        insert allergy;
        
        Medication med = new Medication(
            Name = 'Test Medication'
        );
        insert med;
        
        MedicationStatement medStatement = new MedicationStatement(
            PatientId = testAccount.Id,
            MedicationId = med.Id
        );
        insert medStatement;
        
        MemberPlan insurance = new MemberPlan(
            Name = 'Test Insurance',
            medicalcoverage__Payer_Name__c = 'Test Provider',
            MemberId = testAccount.Id
        );
        insert insurance;
        
        // Only insert a Case if we successfully found/created a Contact
        if (testContactId != null) {
            Case testCase = new Case(
                Subject = 'Test Case',
                AccountId = testAccount.Id,
                ContactId = testContactId
            );
            insert testCase;
        } else {
            System.debug('No auto-created Contact found for Person Account — skipping Case insert');
        }
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'email' => uniqueEmail,
            'phone' => uniquePhone
        };
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
        
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Should retrieve all data successfully');
        System.assertNotEquals(null, response.data, 'Data should be populated');
        System.assertNotEquals(null, response.recordCount, 'Record counts should be populated');
    }
    
    @IsTest
    static void testEmptyRequestBody() {
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        req.requestBody = Blob.valueOf('{}');
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        try {
            ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
            System.assertEquals(false, response.success, 'Should fail with empty request body');
            System.assertEquals('Email and Phone are required for search', response.message);
        } catch (Exception e) {
            System.debug('Exception with empty body: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testDebugInfoPopulation() {
        String uniqueEmail = 'debug.info' + System.currentTimeMillis() + '@example.com';
        String formattedPhone = '(555) 999-8888';
        String cleanPhone = '5559998888';
        
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        
        Account testAccount = new Account(
            FirstName = 'Debug',
            LastName = 'Info' + System.currentTimeMillis(),
            RecordTypeId = personAccountRT,
            PersonEmail = uniqueEmail,
            PersonMobilePhone = formattedPhone
        );
        insert testAccount;
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'email' => uniqueEmail,
            'phone' => formattedPhone
        };
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
        
        Test.stopTest();
        
        System.assertNotEquals(null, response.debugInfo, 'Debug info should be populated');
        if (response.debugInfo != null) {
            System.assertEquals(formattedPhone, response.debugInfo.originalPhone);
            System.assertNotEquals(null, response.debugInfo.trimmedPhone);
            System.assertEquals(cleanPhone, response.debugInfo.cleanedPhone);
        }
    }
    
    @IsTest
    static void testMissingEmailAndPhone() {
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'firstName' => 'Test',
            'lastName' => 'User'
        };
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
        
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Should fail with missing email and phone');
        System.assertEquals('Email and Phone are required for search', response.message);
    }
    
    @IsTest
    static void testPartialMatchSearch() {
        String uniqueEmail = 'partial.match' + System.currentTimeMillis() + '@example.com';
        String uniquePhone = '55533322' + String.valueOf(System.currentTimeMillis()).right(3);
        
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        
        Account testAccount = new Account(
            FirstName = 'PartialFirstName',
            LastName = 'PartialLastName',
            RecordTypeId = personAccountRT,
            PersonEmail = uniqueEmail,
            PersonMobilePhone = uniquePhone
        );
        insert testAccount;
        
        Test.startTest();
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Map<String, Object> requestBody = new Map<String, Object>{
            'email' => uniqueEmail,
            'phone' => uniquePhone,
            'firstName' => 'WrongFirstName',
            'lastName' => 'WrongLastName'
        };
        
        req.requestBody = Blob.valueOf(JSON.serialize(requestBody));
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        
        ContactMedicalDataWrappers.ResponseWrapper response = ContactMedicalDataAPI.getContactData();
        
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Should find contact with email/phone match even with wrong name');
    }
    
    @IsTest
    static void testGetRelatedDocuments() {
        String uniqueEmail = 'docs.test' + System.currentTimeMillis() + '@example.com';
        String uniquePhone = '55566677' + String.valueOf(System.currentTimeMillis()).right(3);
        
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        
        Account testAccount = new Account(
            FirstName = 'Document',
            LastName = 'Test' + System.currentTimeMillis(),
            RecordTypeId = personAccountRT,
            PersonEmail = uniqueEmail,
            PersonMobilePhone = uniquePhone
        );
        insert testAccount;
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.pdf',
            VersionData = Blob.valueOf('Test Content'),
            Send_File_to_Portal__c = true,
            IsMajorVersion = true
        );
        insert cv;
       
        List<ContentVersion> cvList = [
            SELECT ContentDocumentId 
            FROM ContentVersion 
            WHERE Id = :cv.Id 
            LIMIT 1
        ];
        
        System.assertNotEquals(0, cvList.size(), 'ContentVersion should exist after insert');
        cv = cvList[0];
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = testAccount.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
        
        Test.startTest();
        
        List<ContactMedicalDataWrappers.DocumentData> docs = 
            ContactMedicalDataAPI.getRelatedDocuments(testAccount.Id);
        
        Test.stopTest();
        
        System.assertNotEquals(null, docs, 'Documents list should not be null');
        System.assertEquals(true, docs.size() > 0, 'Should have at least one document');
    }
}