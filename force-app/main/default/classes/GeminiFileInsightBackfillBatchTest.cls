@IsTest(SeeAllData=true)
private class GeminiFileInsightBackfillBatchTest {
    @IsTest
    static void testExecuteAccountLinkedFile() {
        Account testAccount = FileStorageApexTestFactory.getTestAccount();
        ContentVersion cv = new ContentVersion(
            Title = 'Account Linked Doc',
            PathOnClient = 'AccountDoc.pdf',
            VersionData = Blob.valueOf('PDF content here'),
            FirstPublishLocationId = testAccount.Id,
            Source__c = 'Metriport'
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId, Title, FileType
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        Test.startTest();
        GeminiFileInsightBackfillBatch batch =
            new GeminiFileInsightBackfillBatch(true, true, cv.Id);

        Database.QueryLocator queryLocator = batch.start(null);
        System.assertNotEquals(
            null,
            queryLocator,
            'QueryLocator should not be null.'
        );

        batch.execute(null, new List<ContentVersion>{ cv });
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(1, batch.totalProcessed);
        System.assertEquals(1, batch.totalFailed);
        System.assertEquals(0, batch.totalSkipped);
    }

    @IsTest
    static void testExecuteNonAccountLinkedSkipped() {
        ContentVersion cv = new ContentVersion(
            Title = 'Non Account Doc',
            PathOnClient = 'NonAccount.txt',
            VersionData = Blob.valueOf('Not linked to account')
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId, Title, FileType
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        Test.startTest();
        GeminiFileInsightBackfillBatch batch =
            new GeminiFileInsightBackfillBatch(false, false, cv.Id);

        batch.execute(null, new List<ContentVersion>{ cv });
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(1, batch.totalProcessed);
        System.assertEquals(1, batch.totalSkipped);
        System.assertEquals(0, batch.totalSuccess);
        System.assertEquals(0, batch.totalFailed);
    }

    @IsTest
    static void testFinishZeroProcessed() {
        Test.startTest();
        GeminiFileInsightBackfillBatch batch =
            new GeminiFileInsightBackfillBatch(null, null, null);

        batch.finish(null);
        Test.stopTest();

        System.assertEquals(0, batch.totalProcessed);
    }
}