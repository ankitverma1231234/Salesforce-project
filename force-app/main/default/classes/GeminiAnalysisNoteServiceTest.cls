@isTest(SeeAllData=true)
private class GeminiAnalysisNoteServiceTest {

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
    static void testInsertAndRetrieveAnalysis() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createTestCv(acc, 'Test Note Doc', 'Note_Doc.csv', Blob.valueOf('test'));
        Id cdId = cv.ContentDocumentId;

        GeminiFileInsightsController.AnalysisBundleWrapper bundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = cdId;
        bundle.analysisTitle = 'Test Document - AI Summary';
        bundle.plainTextContext = 'Test Context';

        Test.startTest();
        GeminiAnalysisNoteService.upsertAnalysisNote(cdId, acc.Id, bundle);
        
        GeminiFileInsightsController.AnalysisBundleWrapper retrievedBundle = 
            GeminiAnalysisNoteService.getStoredAnalysis(cdId);
        Test.stopTest();

        System.assertNotEquals(null, retrievedBundle, 'Stored analysis should be retrieved');
        System.assertEquals(bundle.analysisTitle, retrievedBundle.analysisTitle, 'Stored title should match');
    }

    @isTest
    static void testStalenessCheck() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createTestCv(acc, 'Stale Check Doc', 'Stale_Doc.csv', Blob.valueOf('test 1'));
        Id cdId = cv.ContentDocumentId;

        GeminiFileInsightsController.AnalysisBundleWrapper bundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = cdId;
        bundle.sourceLatestVersionId = cv.Id;
        GeminiAnalysisNoteService.upsertAnalysisNote(cdId, acc.Id, bundle);

        System.assertEquals(true, GeminiAnalysisNoteService.hasFreshAnalysis(cdId), 'Should be fresh initially');

        Test.startTest();
        ContentVersion newVersion = new ContentVersion(
            ContentDocumentId = cdId,
            Title = 'Stale Check Doc',
            PathOnClient = 'Stale_Doc.csv',
            VersionData = Blob.valueOf('test 2'),
            IsMajorVersion = true
        );
        insert newVersion;
        Test.stopTest();

        System.assertEquals(true, GeminiAnalysisNoteService.isAnalysisStale(cdId), 'Should be stale after new version');
    }

    @isTest
    static void testMissingData() {
        Id dummyId = '069000000000000AAA';
        
        Test.startTest();
        GeminiFileInsightsController.AnalysisBundleWrapper retrieved = GeminiAnalysisNoteService.getStoredAnalysis(dummyId);
        Boolean isStale = GeminiAnalysisNoteService.isAnalysisStale(dummyId);
        Test.stopTest();
        
        System.assertEquals(null, retrieved, 'Should return null for missing document');
        System.assertEquals(true, isStale, 'Missing analysis should be considered stale');
    }

    @isTest
    static void testSameTitleFilesDoNotOverwriteEachOther() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion firstCv = createTestCv(acc, 'Duplicate Title Doc', 'Duplicate_Title_1.csv', Blob.valueOf('first'));
        ContentVersion secondCv = createTestCv(acc, 'Duplicate Title Doc', 'Duplicate_Title_2.csv', Blob.valueOf('second'));

        GeminiFileInsightsController.AnalysisBundleWrapper firstBundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        firstBundle.sourceDocumentId = firstCv.ContentDocumentId;
        firstBundle.sourceLatestVersionId = firstCv.Id;
        firstBundle.analysisTitle = 'First Analysis';

        GeminiFileInsightsController.AnalysisBundleWrapper secondBundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        secondBundle.sourceDocumentId = secondCv.ContentDocumentId;
        secondBundle.sourceLatestVersionId = secondCv.Id;
        secondBundle.analysisTitle = 'Second Analysis';

        Test.startTest();
        GeminiAnalysisNoteService.upsertAnalysisNote(firstCv.ContentDocumentId, acc.Id, firstBundle);
        GeminiAnalysisNoteService.upsertAnalysisNote(secondCv.ContentDocumentId, acc.Id, secondBundle);
        Test.stopTest();

        String firstName = GeminiAnalysisNoteService.buildNoteTitle('Duplicate Title Doc', firstCv.ContentDocumentId);
        String secondName = GeminiAnalysisNoteService.buildNoteTitle('Duplicate Title Doc', secondCv.ContentDocumentId);

        System.assertNotEquals(firstName, secondName, 'Same-title source files should produce unique attachment names');

        List<Attachment> storedAttachments = [
            SELECT Id, Name
            FROM Attachment
            WHERE ParentId = :acc.Id
              AND Name IN :new Set<String>{ firstName, secondName }
        ];
        System.assertEquals(2, storedAttachments.size(), 'Both same-title analysis attachments should survive');
    }
}