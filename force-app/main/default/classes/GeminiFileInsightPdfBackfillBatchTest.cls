@isTest(SeeAllData=true)
private class GeminiFileInsightPdfBackfillBatchTest {

    private static ContentVersion createAccountLinkedFile(Account acc, String title) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.txt',
            VersionData = Blob.valueOf('Clinical test content'),
            IsMajorVersion = true
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId, Title, FileType
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        return cv;
    }

    @isTest
    static void testExecuteCreatesPdfFromStoredAnalysis() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createAccountLinkedFile(acc, 'PDF Batch Source');

        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = String.valueOf(cv.ContentDocumentId);
        bundle.sourceLatestVersionId = String.valueOf(cv.Id);
        bundle.analysisTitle = 'PDF Batch Source - AI Generated Summary';
        bundle.parentRecordId = String.valueOf(acc.Id);
        bundle.sections = new Map<String, String>{
            'summary' => '<p>Stored analysis ready for PDF.</p>'
        };

        GeminiAnalysisNoteService.upsertAnalysisNote(cv.ContentDocumentId, acc.Id, bundle);

        Test.startTest();
        GeminiFileInsightPdfBackfillBatch batch = new GeminiFileInsightPdfBackfillBatch(false);
        batch.execute(null, new List<ContentVersion>{ cv });
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(1, batch.totalProcessed);
        System.assertEquals(1, batch.totalSuccess);
        System.assertEquals(0, batch.totalFailed);

        List<ContentVersion> aiFiles = [
            SELECT Id, ContentDocumentId, Title, Source__c, Related_File__c
            FROM ContentVersion
            WHERE Related_File__c = :cv.ContentDocumentId
              AND Source__c = 'AI'
              AND IsLatest = true
        ];
        System.assertEquals(1, aiFiles.size(), 'PDF batch should create one AI file for the source');
    }

    @isTest
    static void testExecuteSkipsWhenStoredAnalysisMissing() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createAccountLinkedFile(acc, 'PDF Batch Missing Note');

        Test.startTest();
        GeminiFileInsightPdfBackfillBatch batch = new GeminiFileInsightPdfBackfillBatch(false);
        System.assertNotEquals(null, batch.start(null), 'Start should return a query locator');
        batch.execute(null, new List<ContentVersion>{ cv });
        batch.finish(null);
        Test.stopTest();

        System.assertEquals(1, batch.totalProcessed);
        System.assertEquals(1, batch.totalSkipped);
        System.assertEquals(0, batch.totalSuccess);
        System.assertEquals(0, batch.totalFailed);
    }

    @isTest
    static void testExecuteSkipsNonAccountAndExistingAi() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        ContentVersion nonAccountCv = new ContentVersion(
            Title = 'PDF Batch Non Account',
            PathOnClient = 'PDF Batch Non Account.txt',
            VersionData = Blob.valueOf('No account link'),
            IsMajorVersion = true
        );
        insert nonAccountCv;
        nonAccountCv = [
            SELECT Id, ContentDocumentId, Title, FileType
            FROM ContentVersion
            WHERE Id = :nonAccountCv.Id
        ];

        ContentVersion sourceWithAi = createAccountLinkedFile(acc, 'PDF Batch Existing AI Source');
        ContentVersion aiCv = new ContentVersion(
            Title = 'PDF Batch Existing AI Source - AI Generated Summary',
            PathOnClient = 'PDF Batch Existing AI Source - AI Generated Summary.pdf',
            VersionData = Blob.valueOf('Existing AI PDF'),
            IsMajorVersion = true,
            Source__c = 'AI',
            Related_File__c = sourceWithAi.ContentDocumentId,
            FirstPublishLocationId = acc.Id
        );
        insert aiCv;

        Test.startTest();
        GeminiFileInsightPdfBackfillBatch batch = new GeminiFileInsightPdfBackfillBatch(false);
        batch.execute(null, new List<ContentVersion>{ nonAccountCv, sourceWithAi });
        Test.stopTest();

        System.assertEquals(2, batch.totalProcessed);
        System.assertEquals(2, batch.totalSkipped);
        System.assertEquals(0, batch.totalSuccess);
    }
}