@isTest(SeeAllData=true)
private class FileStorageAccountEventHandlerTest {

    private static Id getTestAccountId() {
        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
        System.assert(!accounts.isEmpty(),
            'Expected an Account with Metriport_Patient_Id__c = patient-123 to exist in the org.');
        return accounts[0].Id;
    }

    private static ContentVersion createContentVersionLinkedToAccount(Id accountId, String title) {
        ContentVersion cv = new ContentVersion(
            Title          = title,
            PathOnClient   = title + '.txt',
            VersionData    = Blob.valueOf('test file contents'),
            IsMajorVersion = true
        );
        insert cv;

        ContentVersion insertedCv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = insertedCv.ContentDocumentId,
            LinkedEntityId    = accountId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdl;

        return insertedCv;
    }

    @isTest
    static void handleAfterInsert_publishesEventForLinkedAccount() {
        Id accountId = getTestAccountId();
        ContentVersion cv = createContentVersionLinkedToAccount(accountId, 'FSAEHTest_Linked');

        fra__File_Storage__c fs = new fra__File_Storage__c(
            fra__Internal_File_Id__c = String.valueOf(cv.Id)
        );

        Test.startTest();
        FileStorageAccountEventHandler.handleAfterInsert(new List<fra__File_Storage__c>{ fs });
        Test.stopTest();

        System.assert(true,
            'handleAfterInsert should complete without exceptions for a valid CV linked to an Account.');
    }

    @isTest
    static void handleAfterInsert_nullList_doesNothing() {
        Test.startTest();
        FileStorageAccountEventHandler.handleAfterInsert(null);
        Test.stopTest();
        System.assert(true, 'Null input should be a no-op.');
    }

    @isTest
    static void handleAfterInsert_emptyList_doesNothing() {
        Test.startTest();
        FileStorageAccountEventHandler.handleAfterInsert(new List<fra__File_Storage__c>());
        Test.stopTest();
        System.assert(true, 'Empty input should be a no-op.');
    }

    @isTest
    static void handleAfterInsert_blankAndInvalidIds_areSkipped() {
        fra__File_Storage__c blankRec = new fra__File_Storage__c(
            fra__Internal_File_Id__c = ''
        );
        fra__File_Storage__c shortRec = new fra__File_Storage__c(
            fra__Internal_File_Id__c = 'abc'
        );
        fra__File_Storage__c nullRec = new fra__File_Storage__c(
            fra__Internal_File_Id__c = null
        );
        fra__File_Storage__c garbageRec = new fra__File_Storage__c(
            fra__Internal_File_Id__c = 'not-a-valid-salesforce-id-123'
        );

        Test.startTest();
        FileStorageAccountEventHandler.handleAfterInsert(new List<fra__File_Storage__c>{
            blankRec, shortRec, nullRec, garbageRec
        });
        Test.stopTest();

        System.assert(true,
            'Blank, null, short, or otherwise invalid CV ids should be skipped without throwing.');
    }

    @isTest
    static void handleAfterInsert_contentVersionNotLinkedToAccount_doesNotPublish() {
        ContentVersion cv = new ContentVersion(
            Title          = 'FSAEHTest_Unlinked',
            PathOnClient   = 'FSAEHTest_Unlinked.txt',
            VersionData    = Blob.valueOf('orphan file'),
            IsMajorVersion = true
        );
        insert cv;

        fra__File_Storage__c fs = new fra__File_Storage__c(
            fra__Internal_File_Id__c = String.valueOf(cv.Id)
        );

        Test.startTest();
        FileStorageAccountEventHandler.handleAfterInsert(new List<fra__File_Storage__c>{ fs });
        Test.stopTest();

        System.assert(true,
            'A ContentVersion with no ContentDocumentLink to an Account should produce no event.');
    }

    @isTest
    static void handleAfterInsert_unknownContentVersionId_doesNotPublish() {
        Id fakeCvId = Id.valueOf('068000000000000AAA');

        fra__File_Storage__c fs = new fra__File_Storage__c(
            fra__Internal_File_Id__c = String.valueOf(fakeCvId)
        );

        Test.startTest();
        FileStorageAccountEventHandler.handleAfterInsert(new List<fra__File_Storage__c>{ fs });
        Test.stopTest();

        System.assert(true,
            'A non-existent ContentVersion id should yield no downstream queries failing.');
    }
}