@isTest(SeeAllData=true)
private class FileUpsertHelperTest {
    
    class FileMock implements HttpCalloutMock {
        
        public HTTPResponse respond(HTTPRequest req) {
            
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('Test File Content');
            return res;
        }
    }
  
    class FileFailMock implements HttpCalloutMock {
        
        public HTTPResponse respond(HTTPRequest req) {
            
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            return res;
        }
    }
    
  
    private static Account getOrCreatePersonAccount() {
        
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail != null
            AND PersonMobilePhone != null
            LIMIT 1
        ];
        
        if (!existingAccounts.isEmpty()) {
            return existingAccounts[0];
        }
        
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();
        
        Account testAcc = new Account(
            FirstName        = 'Existing',
            LastName         = 'Test',
            RecordTypeId     = personAccountRT,
            PersonEmail      = 'existing.test@example.com',
            PersonMobilePhone = '5551234567'
        );
        
        insert testAcc;
        return testAcc;
    }
    
    /* -------------------------------------------------------
TEST 1 — SUCCESS FILE INSERT
------------------------------------------------------- */
    @isTest
    static void testProcessFilesSuccess() {
        
        Test.setMock(HttpCalloutMock.class, new FileMock());
        
        Account acc = getOrCreatePersonAccount();
        
        List<Map<String,Object>> records = new List<Map<String,Object>>();
        
        Map<String,Object> fileData = new Map<String,Object>{
            'title'         => 'Test File',
                'file_name'     => 'sample.pdf',
                'document_url'  => 'https://test.com/sample.pdf',
                'Accountid'     => acc.Id,
                'description'   => 'Test Description',
                'is_deleted'    => false,
                'document_type' => 'Lab',
                'source_type'   => 'Metriport',
                'category'      => 'Miscellaneous Documents',
                'created_date'  => '2026-06-12T00:00:00.000Z'
                };
                    
                    records.add(fileData);
        
        Test.startTest();
        List<Map<String,Object>> result = FileUpsertHelper.processFiles(records);
        Test.stopTest();
        
        System.assertEquals(1, result.size());
        System.assertEquals(true, result[0].get('success'));
        
        List<ContentVersion> files = [
            SELECT Id, Title, Send_File_to_Portal__c
            FROM ContentVersion
            WHERE Title = 'Test File'
        ];
        
        System.assert(!files.isEmpty(), 'ContentVersion should be created');
    }
    
    /* -------------------------------------------------------
TEST 2 — UPDATE CHECKBOX VIA "id" (068)
------------------------------------------------------- */
    @isTest
    static void testUpdateCheckboxViaId() {
        
        Test.setMock(HttpCalloutMock.class, new FileMock());
        
        Account acc = getOrCreatePersonAccount();
        
        ContentVersion cv = new ContentVersion(
            Title                  = 'Update Test File',
            PathOnClient           = 'test.pdf',
            VersionData            = Blob.valueOf('test data'),
            FirstPublishLocationId = acc.Id,
            Send_File_to_Portal__c = true
        );
        
        insert cv;
        
        ContentVersion insertedCV = [
            SELECT Id, Send_File_to_Portal__c
            FROM ContentVersion
            WHERE Title = 'Update Test File'
            LIMIT 1
        ];
        
        List<Map<String,Object>> records = new List<Map<String,Object>>();
        
        Map<String,Object> updateData = new Map<String,Object>{
            'id'         => insertedCV.Id,
                'is_deleted' => true
                };
                    
                    records.add(updateData);
        
        Test.startTest();
        List<Map<String,Object>> result = FileUpsertHelper.processFiles(records);
        Test.stopTest();
        
        ContentVersion updatedCV = [
            SELECT Send_File_to_Portal__c
            FROM ContentVersion
            WHERE Id = :insertedCV.Id
        ];
        
        System.assertEquals(1, result.size());
        System.assertEquals(true,  result[0].get('success'));
        System.assertEquals(false, updatedCV.Send_File_to_Portal__c);
    }
    
    /* -------------------------------------------------------
TEST 3 — UNCHECK fra__File_Storage__c VIA "recordid" (ar3)
------------------------------------------------------- */
    /* -------------------------------------------------------
TEST 3 — UNCHECK fra__File_Storage__c VIA "recordid" (ar3)
------------------------------------------------------- */
    @isTest
    static void testUpdateFileStorageViaRecordId() {
        
        Account acc = getOrCreatePersonAccount();
        
        fra__Entity_Storage__c entityStorage = new fra__Entity_Storage__c(
            fra__Entity_Folder_Name__c = 'TestFolder'
        );
        
        insert entityStorage;
        
        fra__File_Storage__c fileStorage = new fra__File_Storage__c(
            Send_to_Portal__c        = true,
            fra__Entity_Storage__c   = entityStorage.Id
        );
        
        insert fileStorage;
        
        fra__File_Storage__c insertedFS = [
            SELECT Id, Send_to_Portal__c
            FROM fra__File_Storage__c
            WHERE Id = :fileStorage.Id
            LIMIT 1
        ];
        
        List<Map<String,Object>> records = new List<Map<String,Object>>();
        
        Map<String,Object> deleteData = new Map<String,Object>{
            'recordid'   => insertedFS.Id,
                'is_deleted' => true
                };
                    
                    records.add(deleteData);
        
        Test.startTest();
        List<Map<String,Object>> result = FileUpsertHelper.processFiles(records);
        Test.stopTest();
        
        fra__File_Storage__c updatedFS = [
            SELECT Send_to_Portal__c
            FROM fra__File_Storage__c
            WHERE Id = :insertedFS.Id
        ];
        
    }
    
    /* -------------------------------------------------------
TEST 4 — DOWNLOAD FAILURE
------------------------------------------------------- */
    @isTest
    static void testDownloadFailure() {
        
        Test.setMock(HttpCalloutMock.class, new FileFailMock());
        
        Account acc = getOrCreatePersonAccount();
        
        List<Map<String,Object>> records = new List<Map<String,Object>>();
        
        Map<String,Object> fileData = new Map<String,Object>{
            'title'        => 'Fail File',
                'file_name'    => 'sample.pdf',
                'document_url' => 'https://test.com/sample.pdf',
                'Accountid'    => acc.Id,
                'is_deleted'   => false
                };
                    
                    records.add(fileData);
        
        Test.startTest();
        List<Map<String,Object>> result = FileUpsertHelper.processFiles(records);
        Test.stopTest();
        
        System.assertEquals(1,     result.size());
        System.assertEquals(false, result[0].get('success'));
        System.assertEquals('File download failed', result[0].get('message'));
    }
    
    /* -------------------------------------------------------
TEST 5 — MISSING document_url OR file_name
------------------------------------------------------- */
    @isTest
    static void testMissingRequiredFields() {
        
        Account acc = getOrCreatePersonAccount();
        
        List<Map<String,Object>> records = new List<Map<String,Object>>();
        
        Map<String,Object> fileData = new Map<String,Object>{
            'title'      => 'Missing Fields File',
                'Accountid'  => acc.Id,
                'is_deleted' => false
                };
                    
                    records.add(fileData);
        
        Test.startTest();
        List<Map<String,Object>> result = FileUpsertHelper.processFiles(records);
        Test.stopTest();
        
        System.assertEquals(1,     result.size());
        System.assertEquals(false, result[0].get('success'));
        System.assertEquals('Missing document_url or file_name', result[0].get('message'));
    }
    
    /* -------------------------------------------------------
TEST 6 — NULL RECORDS LIST
------------------------------------------------------- */
    @isTest
    static void testNullRecords() {
        
        Test.startTest();
        List<Map<String,Object>> result = FileUpsertHelper.processFiles(null);
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
    
    @isTest
    static void testEmptyRecords() {
        
        Test.startTest();
        List<Map<String,Object>> result = FileUpsertHelper.processFiles(
            new List<Map<String,Object>>()
        );
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
}