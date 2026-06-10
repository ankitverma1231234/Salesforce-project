@IsTest
private class AccountFileExternalSyncServiceTest {

    private class MockBatchExecutor implements AccountFileExternalSyncService.FileSyncBatchExecutor {
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
            return jobId;
        }
    }

    private static ContentVersion createTestFile() {

        Account pa = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'TestFile.pdf',
            VersionData = Blob.valueOf('Test Content'),
            FirstPublishLocationId = pa.Id
        );
        insert cv;

        return [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
    }

    @IsTest(SeeAllData=true)
    static void testQueueContentDocumentSync_Success() {

        ContentVersion cv = createTestFile();

        AccountFileExternalSyncService.batchExecutor = new MockBatchExecutor();

        Test.startTest();

        AccountFileExternalSyncService.SyncResult result =
            AccountFileExternalSyncService.queueContentDocumentSync(
                new List<Id>{cv.ContentDocumentId}
            );

        Test.stopTest();

        System.assertEquals(true, result.queued);
        System.assertEquals(false, result.failed);
        System.assertEquals(false, result.skippedDuplicate);
        System.assertEquals(1, result.contentDocumentCount);
        System.assertNotEquals(null, result.jobId);
    }

    @IsTest(SeeAllData=true)
    static void testQueueContentDocumentSync_DuplicateRequest() {

        ContentVersion cv = createTestFile();

        AccountFileExternalSyncService.batchExecutor = new MockBatchExecutor();

        Test.startTest();

        AccountFileExternalSyncService.SyncResult firstResult =
            AccountFileExternalSyncService.queueContentDocumentSync(
                new List<Id>{cv.ContentDocumentId}
            );

        AccountFileExternalSyncService.SyncResult secondResult =
            AccountFileExternalSyncService.queueContentDocumentSync(
                new List<Id>{cv.ContentDocumentId}
            );

        Test.stopTest();

        System.assertEquals(true, firstResult.queued);
        System.assertEquals(true, secondResult.skippedDuplicate);
    }

    @IsTest
    static void testQueueContentDocumentSync_EmptyList() {

        AccountFileExternalSyncService.batchExecutor = new MockBatchExecutor();

        AccountFileExternalSyncService.SyncResult result =
            AccountFileExternalSyncService.queueContentDocumentSync(
                new List<Id>()
            );

        System.assertEquals(false, result.queued);
        System.assertEquals(0, result.contentDocumentCount);
    }

    @IsTest
    static void testQueueContentDocumentSync_NullList() {

        AccountFileExternalSyncService.batchExecutor = new MockBatchExecutor();

        AccountFileExternalSyncService.SyncResult result =
            AccountFileExternalSyncService.queueContentDocumentSync(null);

        System.assertEquals(false, result.queued);
        System.assertEquals(0, result.contentDocumentCount);
    }

    @IsTest(SeeAllData=true)
    static void testBuildContentDocumentQuery() {

        ContentVersion cv = createTestFile();

        String query =
            AccountFileExternalSyncService.buildContentDocumentQuery(
                new Set<Id>{cv.ContentDocumentId}
            );

        System.assert(
            query.contains(String.valueOf(cv.ContentDocumentId))
        );
    }
}