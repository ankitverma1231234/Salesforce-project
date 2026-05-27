@isTest(SeeAllData=true)
private class FileUpsertHelperTest {

    /* -------------------------------------------------------
       MOCK CALLOUT
    ------------------------------------------------------- */
    class FileMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('Test File Content');
            return res;
        }
    }

    /* -------------------------------------------------------
       HELPER: GET OR CREATE PERSON ACCOUNT
    ------------------------------------------------------- */
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
            FirstName = 'Existing',
            LastName = 'Test',
            RecordTypeId = personAccountRT,
            PersonEmail = 'existing.test@example.com',
            PersonMobilePhone = '5551234567'
        );

        insert testAcc;
        return testAcc;
    }

    /* -------------------------------------------------------
       TEST SUCCESS FILE INSERT
    ------------------------------------------------------- */
    @isTest
    static void testProcessFilesSuccess() {

        Test.setMock(HttpCalloutMock.class, new FileMock());

        Account acc = getOrCreatePersonAccount();

        List<Map<String,Object>> records = new List<Map<String,Object>>();

        Map<String,Object> fileData = new Map<String,Object>{
            'title'        => 'Test File',
            'file_name'    => 'sample.pdf',
            'document_url' => 'https://test.com/sample.pdf',
            'Accountid'    => acc.Id,
            'description'  => 'Test Description',
            'is_deleted'   => false
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
        System.assertEquals(true, files[0].Send_File_to_Portal__c);
    }

    /* -------------------------------------------------------
       TEST UPDATE FLOW (CHECKBOX UNCHECK)
    ------------------------------------------------------- */
    @isTest
    static void testUpdateCheckbox() {

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

        System.assertEquals(false, updatedCV.Send_File_to_Portal__c);
    }

    /* -------------------------------------------------------
       TEST DOWNLOAD FAILURE
    ------------------------------------------------------- */
    class FileFailMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            return res;
        }
    }

    @isTest
    static void testDownloadFailure() {

        Test.setMock(HttpCalloutMock.class, new FileFailMock());

        Account acc = getOrCreatePersonAccount();

        List<Map<String,Object>> records = new List<Map<String,Object>>();

        Map<String,Object> fileData = new Map<String,Object>{
            'title'        => 'Fail File',
            'file_name'    => 'sample.pdf',
            'document_url' => 'https://test.com/sample.pdf',
            'Accountid'    => acc.Id
        };

        records.add(fileData);

        Test.startTest();
        List<Map<String,Object>> result = FileUpsertHelper.processFiles(records);
        Test.stopTest();

        System.assertEquals(false, result[0].get('success'));
    }

}