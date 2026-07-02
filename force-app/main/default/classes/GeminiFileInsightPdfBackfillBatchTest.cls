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
        Test.stopTest();

        System.assertEquals(1, batch.totalProcessed);
        System.assertEquals(1, batch.totalSuccess);
        System.assertEquals(0, batch.totalFailed);

        List<ContentVersion> aiFiles = [
            SELECT Id, ContentDocumentId, Title, Source_Type__c, Related_File__c
            FROM ContentVersion
            WHERE Related_File__c = :cv.ContentDocumentId
              AND Source_Type__c = 'AI'
              AND IsLatest = true
        ];
    }

    @isTest
    static void testExecuteSkipsWhenStoredAnalysisMissing() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createAccountLinkedFile(acc, 'PDF Batch Missing Note');

        Test.startTest();
        GeminiFileInsightPdfBackfillBatch batch = new GeminiFileInsightPdfBackfillBatch(false);
        System.assertNotEquals(null, batch.start(null), 'Start should return a query locator');
        batch.execute(null, new List<ContentVersion>{ cv });
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
            Source_Type__c = 'AI',
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

    @isTest
    static void testFinishSkipsGdriveWhenSourceIsAlreadySynced() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createAccountLinkedFile(
            acc,
            'PDF Batch Already Synced'
        );
        Document_Processing_Log__c logRecord =
            FileStorageApexTestFactory.createProcessingLog(cv.Id, false);
        FileStorageApexTestFactory.createFileStorage(
            acc,
            'PDF Batch Already Synced.txt',
            new Map<String, Object>{
                'fra__Internal_File_Id__c' => String.valueOf(cv.Id)
            }
        );

        Set<Id> existingJobIds = getAccountSyncJobIds();
        new GeminiFileInsightPdfBackfillBatch(false, cv.Id).finish(null);
        abortNewAccountSyncJobs(existingJobIds);

        Document_Processing_Log__c unchangedLog = [
            SELECT Ready_for_Gdrive__c
            FROM Document_Processing_Log__c
            WHERE Id = :logRecord.Id
        ];
        System.assertNotEquals(true, unchangedLog.Ready_for_Gdrive__c);
    }

    @isTest
    static void testFinishLeavesGdriveFlagUnchangedWhenUpdateIsDisabled() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createAccountLinkedFile(
            acc,
            'PDF Batch Unsynced'
        );
        Document_Processing_Log__c logRecord =
            FileStorageApexTestFactory.createProcessingLog(cv.Id, false);

        Set<Id> existingJobIds = getAccountSyncJobIds();
        new GeminiFileInsightPdfBackfillBatch(false, cv.Id).finish(null);
        abortNewAccountSyncJobs(existingJobIds);

        Document_Processing_Log__c updatedLog = [
            SELECT Ready_for_Gdrive__c
            FROM Document_Processing_Log__c
            WHERE Id = :logRecord.Id
        ];
        System.assertNotEquals(true, updatedLog.Ready_for_Gdrive__c);
    }

    private static Set<Id> getAccountSyncJobIds() {
        return new Map<Id, AsyncApexJob>([
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AccountFileSyncInitiatorBatch'
        ]).keySet();
    }

    private static void abortNewAccountSyncJobs(Set<Id> existingJobIds) {
        for (AsyncApexJob job : [
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AccountFileSyncInitiatorBatch'
            AND Id NOT IN :existingJobIds
            AND Status IN ('Holding', 'Queued', 'Preparing')
        ]) {
            System.abortJob(job.Id);
        }
    }
}