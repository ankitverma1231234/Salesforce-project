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
            WHERE Name IN :new Set<String>{ firstName, secondName }
        ];
        System.assertEquals(2, storedAttachments.size(), 'Both same-title analysis attachments should survive');
    }

    @isTest
    static void testExactStoredAnalysisWinsWhenManyLegacyCandidatesExist() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createTestCv(acc, 'Heap Safe Doc', 'Heap_Safe_Doc.csv', Blob.valueOf('content'));

        GeminiFileInsightsController.AnalysisBundleWrapper bundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = cv.ContentDocumentId;
        bundle.sourceLatestVersionId = cv.Id;
        bundle.analysisTitle = 'Exact Analysis';

        GeminiAnalysisNoteService.upsertAnalysisNote(cv.ContentDocumentId, acc.Id, bundle);

        List<Attachment> legacyNoise = new List<Attachment>();
        String legacyName = 'Legacy Noise - AI Analysis Store [' + String.valueOf(cv.ContentDocumentId).left(8) + ']';
        String largeContext = '';
        for (Integer i = 0; i < 1000; i++) {
            largeContext += 'noise';
        }
        for (Integer i = 0; i < 20; i++) {
            GeminiFileInsightsController.AnalysisBundleWrapper noiseBundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
            noiseBundle.sourceDocumentId = '069000000000000AAA';
            noiseBundle.analysisTitle = 'Noise ' + i;
            noiseBundle.plainTextContext = largeContext;
            legacyNoise.add(new Attachment(
                ParentId = acc.Id,
                Name = legacyName,
                Body = Blob.valueOf(JSON.serialize(noiseBundle)),
                ContentType = 'application/json'
            ));
        }
        insert legacyNoise;

        Test.startTest();
        GeminiFileInsightsController.AnalysisBundleWrapper retrieved =
            GeminiAnalysisNoteService.getStoredAnalysis(cv.ContentDocumentId);
        Test.stopTest();

        System.assertNotEquals(null, retrieved, 'Exact stored analysis should still be found');
        System.assertEquals('Exact Analysis', retrieved.analysisTitle, 'Exact full-id note should win over legacy noise');
    }

    @isTest
    static void testLegacyStoredAnalysisFallbackStillWorks() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createTestCv(acc, 'Legacy Stored Doc', 'Legacy_Stored_Doc.csv', Blob.valueOf('content'));

        GeminiFileInsightsController.AnalysisBundleWrapper bundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = cv.ContentDocumentId;
        bundle.sourceLatestVersionId = cv.Id;
        bundle.analysisTitle = 'Legacy Analysis';

        insert new Attachment(
            ParentId = acc.Id,
            Name = 'Legacy Stored Doc - AI Analysis Store [' + String.valueOf(cv.ContentDocumentId).left(8) + ']',
            Body = Blob.valueOf(JSON.serialize(bundle)),
            ContentType = 'application/json'
        );

        Test.startTest();
        GeminiFileInsightsController.AnalysisBundleWrapper retrieved =
            GeminiAnalysisNoteService.getStoredAnalysis(cv.ContentDocumentId);
        Test.stopTest();

        System.assertNotEquals(null, retrieved, 'Legacy stored analysis should still be available');
        System.assertEquals('Legacy Analysis', retrieved.analysisTitle);
    }

    @isTest
    static void testAttachmentHelpersAndBodyRefresh() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        ContentVersion cv = createTestCv(acc, 'Attachment Helper Doc', 'Attachment_Helper_Doc.csv', Blob.valueOf('content'));

        GeminiFileInsightsController.AnalysisBundleWrapper bundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = cv.ContentDocumentId;
        bundle.sourceLatestVersionId = cv.Id;
        bundle.analysisTitle = 'Original Analysis';

        Id attachmentId = GeminiAnalysisNoteService.upsertAnalysisNote(cv.ContentDocumentId, acc.Id, bundle);

        Attachment metadataOnly = GeminiAnalysisNoteService.getStoredAnalysisAttachment(cv.ContentDocumentId, false);
        Attachment withBody = GeminiAnalysisNoteService.getStoredAnalysisAttachment(cv.ContentDocumentId, true);
        System.assertEquals(attachmentId, metadataOnly.Id, 'Metadata lookup should return the stored attachment');
        System.assertEquals(attachmentId, withBody.Id, 'Body lookup should return the stored attachment');
        System.assertNotEquals(null, withBody.Body, 'Body lookup should hydrate attachment body');

        bundle.analysisTitle = 'Updated Analysis';
        GeminiAnalysisNoteService.updateAnalysisNoteBody(attachmentId, bundle);

        GeminiFileInsightsController.AnalysisBundleWrapper refreshed =
            GeminiAnalysisNoteService.getStoredAnalysis(cv.ContentDocumentId);
        System.assertEquals('Updated Analysis', refreshed.analysisTitle, 'Body refresh should be readable');
    }
}