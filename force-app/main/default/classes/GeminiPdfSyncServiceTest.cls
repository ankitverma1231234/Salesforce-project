@isTest(SeeAllData=true)
private class GeminiPdfSyncServiceTest {

    static ContentVersion createTestCv(Account acc, String title, String path, Blob data) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = path,
            VersionData = data,
            IsMajorVersion = true
        );
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = cdId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    }

    @isTest
    static void testSyncPdfFromStoredAnalysis() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createTestCv(acc, 'My File To Sync', 'My_File_To_Sync.csv', Blob.valueOf('Sync text logic'));
        Id docId = cv.ContentDocumentId;

        GeminiFileInsightsController.AnalysisBundleWrapper bundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = String.valueOf(docId);
        bundle.sourceLatestVersionId = String.valueOf(cv.Id);
        bundle.analysisTitle = 'My File AI Notes';
        bundle.parentRecordId = String.valueOf(acc.Id);
        bundle.sections = new Map<String, String>{
            'summary' => '<p>Clinical summary content.</p>'
        };
        
        GeminiAnalysisNoteService.upsertAnalysisNote(docId, acc.Id, bundle);

        Test.setCurrentPage(Page.GeminiFileInsightsPdf);

        Test.startTest();
        GeminiFileInsightsController.SavedFileResult result = GeminiPdfSyncService.syncPdfFromStoredAnalysis(docId);
        Test.stopTest();

        System.assertNotEquals(null, result, 'SavedFileResult should not be null');
        System.assertNotEquals(null, result.contentDocumentId, 'A new ContentDocumentId should be assigned for the PDF');
        System.assertEquals('My File AI Notes', result.title, 'The resulting PDF should take the title from the bundle');

        List<ContentVersion> createdPdfs = [
            SELECT Id, Title, Source_Type__c, Related_File__c, Description
            FROM ContentVersion
            WHERE Id = :result.contentVersionId
        ];
        System.assertEquals(1, createdPdfs.size(), 'A ContentVersion should have been inserted');
        System.assertEquals(docId, createdPdfs[0].Related_File__c, 'Generated PDF should point back to the source document');
    }

    @isTest
    static void testSyncPdfFromStoredAnalysis_NoStoredAnalysis() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createTestCv(acc, 'No Stored Analysis', 'No_Stored_Analysis.csv', Blob.valueOf('Missing note'));

        Boolean didThrow = false;
        Test.startTest();
        try {
            GeminiPdfSyncService.syncPdfFromStoredAnalysis(cv.ContentDocumentId);
            System.assert(false, 'Expected an exception when the stored analysis note is missing');
        } catch (Exception e) {
            didThrow = true;
            System.assertNotEquals(null, e, 'Missing stored analysis should raise an exception');
        }
        Test.stopTest();
        System.assertEquals(true, didThrow, 'Missing stored analysis should throw');
    }

    @isTest
    static void testSyncPdfFromStoredAnalysis_EmptyStoredBundle() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createTestCv(acc, 'Empty Bundle', 'Empty_Bundle.csv', Blob.valueOf('Empty note'));

        GeminiFileInsightsController.AnalysisBundleWrapper bundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = String.valueOf(cv.ContentDocumentId);
        bundle.sourceLatestVersionId = String.valueOf(cv.Id);
        bundle.analysisTitle = 'Empty Bundle - AI Notes';
        bundle.parentRecordId = String.valueOf(acc.Id);
        bundle.sections = new Map<String, String>{
            'summary' => '<p>N/A</p>',
            'medicalHistory' => '<p>-</p>'
        };
        GeminiAnalysisNoteService.upsertAnalysisNote(cv.ContentDocumentId, acc.Id, bundle);

        Boolean didThrow = false;
        Test.startTest();
        try {
            GeminiPdfSyncService.syncPdfFromStoredAnalysis(cv.ContentDocumentId);
            System.assert(false, 'Expected an exception when the stored analysis has no renderable content');
        } catch (Exception e) {
            didThrow = true;
            System.assertNotEquals(null, e, 'Empty stored analysis should raise an exception');
        }
        Test.stopTest();
        System.assertEquals(true, didThrow, 'Empty stored analysis should throw');

        ContentVersion refreshedSource = [
            SELECT Id, Is_AI_Summary_Generated__c
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
        System.assertEquals(false, refreshedSource.Is_AI_Summary_Generated__c,
            'Empty stored analysis should mark the source file for retry');
    }
}