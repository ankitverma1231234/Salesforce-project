@IsTest(SeeAllData=true)
private class AccountFileUploaderControllerTest {
    private class MockBatchExecutor
        implements AccountFileExternalSyncService.FileSyncBatchExecutor {
        public Id execute(
            String objectApiName,
            Id jobId,
            Boolean syncContentVersion,
            Boolean syncAttachment,
            Integer queryLimit,
            String contentDocumentQuery,
            String storageProvider,
            String parentId
        ) {
            System.assertEquals('ContentDocument', objectApiName);
            System.assertEquals(true, syncContentVersion);
            System.assertEquals(false, syncAttachment);
            System.assertEquals(100, queryLimit);
            System.assertEquals('Google Drive', storageProvider);
            System.assert(contentDocumentQuery.contains('ContentDocument'));
            return jobId;
        }
    }

    @IsTest
    static void confirmUploadLinksFilesCreatesLogsAndQueuesSync() {
        Account testAccount = getExistingAccount();
        ContentVersion linkedVersion = FileStorageApexTestFactory.createFile(
            testAccount,
            'Already Linked',
            'AlreadyLinked.pdf',
            'linked'
        );
        ContentVersion unlinkedVersion = new ContentVersion(
            Title = 'Needs Link',
            PathOnClient = 'NeedsLink.pdf',
            VersionData = Blob.valueOf('unlinked')
        );
        insert unlinkedVersion;
        unlinkedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :unlinkedVersion.Id
        ];

        AccountFileExternalSyncService.batchExecutor = new MockBatchExecutor();

        AccountFileUploaderController.UploadResult result =
            AccountFileUploaderController.confirmUpload(
                testAccount.Id,
                new List<Id>{
                    linkedVersion.ContentDocumentId,
                    unlinkedVersion.ContentDocumentId
                }
            );

        System.assertEquals(testAccount.Id, result.accountId);
        System.assertNotEquals(null, result.accountName);
        System.assertEquals(2, result.uploadedFiles.size());
        System.assertEquals(2, result.logsCreated);
        System.assertEquals(0, result.logsSkipped);
        System.assertEquals(false, result.logCreationFailed);
        System.assertEquals(true, result.syncQueued);
        System.assertNotEquals(null, result.syncJobId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :testAccount.Id
                AND ContentDocumentId = :unlinkedVersion.ContentDocumentId
            ]
        );
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c IN :new Set<String>{
                    String.valueOf(linkedVersion.Id),
                    String.valueOf(unlinkedVersion.Id)
                }
            ]
        );
    }

    @IsTest
    static void confirmUploadSkipsExistingLogAndDuplicateSync() {
        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Duplicate Upload',
            'DuplicateUpload.pdf',
            'content'
        );
        FileStorageApexTestFactory.createProcessingLog(version.Id, true);
        AccountFileExternalSyncService.batchExecutor = new MockBatchExecutor();

        AccountFileUploaderController.UploadResult first =
            AccountFileUploaderController.confirmUpload(
                testAccount.Id,
                new List<Id>{ version.ContentDocumentId }
            );
        AccountFileUploaderController.UploadResult second =
            AccountFileUploaderController.confirmUpload(
                testAccount.Id,
                new List<Id>{ version.ContentDocumentId }
            );

        System.assertEquals(0, first.logsCreated);
        System.assertEquals(1, first.logsSkipped);
        System.assertEquals(true, first.syncQueued);
        System.assertEquals(true, second.syncSkippedDuplicate);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c = :String.valueOf(version.Id)
            ]
        );
    }

    @IsTest
    static void confirmUploadValidatesInputsAndMissingAccount() {
        Account testAccount = getExistingAccount();
        assertUploadFailure(null, new List<Id>{ Id.valueOf('069000000000001AAA') });
        assertUploadFailure(testAccount.Id, null);
        assertUploadFailure(testAccount.Id, new List<Id>());
        assertUploadFailure(
            Id.valueOf('001000000000001AAA'),
            new List<Id>{ Id.valueOf('069000000000001AAA') }
        );
    }

    private static Account getExistingAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
    }

    private static void assertUploadFailure(Id accountId, List<Id> documentIds) {
        try {
            AccountFileUploaderController.confirmUpload(accountId, documentIds);
            System.assert(false, 'Expected confirmUpload to reject invalid input.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
    }
}