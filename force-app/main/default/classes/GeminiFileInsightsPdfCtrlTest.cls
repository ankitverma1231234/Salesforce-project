@isTest(SeeAllData=true)
private class GeminiFileInsightsPdfCtrlTest {

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
    static void testControllerInitialization() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        ContentVersion cv = createTestCv(acc, 'Pdf Ctrl Target', 'Target.csv', Blob.valueOf('Empty'));
        Id cdId = cv.ContentDocumentId;

        GeminiFileInsightsController.AnalysisBundleWrapper bundle = new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = cdId;
        bundle.analysisTitle = 'Pdf Document AI Summary';
        bundle.parentRecordId = acc.Id;
        bundle.generatedOn = '2023-11-20T10:00:00Z';
        bundle.sections = new Map<String, String>{
            'summary' => '<p>Overview Info</p>',
            'keyFindings' => '<ul><li>Item 1</li></ul>',
            'chiefComplaint' => 'Headache'
        };

        GeminiFileInsightsController.KeyFieldWrapper kf1 = new GeminiFileInsightsController.KeyFieldWrapper();
        kf1.groupName = 'Encounter Details';
        kf1.label = 'Consulting Clinician';
        kf1.value = 'Dr. Smith';

        GeminiFileInsightsController.KeyFieldWrapper kf2 = new GeminiFileInsightsController.KeyFieldWrapper();
        kf2.groupName = 'Encounter Details';
        kf2.label = 'Location';
        kf2.value = 'General Hospital';

        bundle.keyFields = new List<GeminiFileInsightsController.KeyFieldWrapper>{ kf1, kf2 };
        GeminiAnalysisNoteService.upsertAnalysisNote(cdId, acc.Id, bundle);

        Test.setCurrentPage(Page.GeminiFileInsightsPdf);
        ApexPages.currentPage().getParameters().put('contentDocumentId', cdId);

        Test.startTest();
        GeminiFileInsightsPdfController ctrl = new GeminiFileInsightsPdfController();
        Test.stopTest();

        System.assertEquals('Pdf Document AI Summary', ctrl.fileTitle, 'Title should match the stored analysis bundle');
        System.assertEquals(true, ctrl.getHasSummary(), 'Should identify presence of summary');
        System.assertEquals(true, ctrl.getHasKeyFindings(), 'Should identify presence of key findings');
        System.assertEquals(true, ctrl.getHasKeyFields(), 'Should identify presence of key fields');
        System.assertEquals(true, ctrl.getHasOtherSections(), 'Should identify presence of other sections (chief complaint)');
        
        System.assertEquals('Dr. Smith', ctrl.consultingClinician, 'Should correctly extract consulting clinician from keyfields');
        System.assertEquals('General Hospital', ctrl.documentLocation, 'Should correctly extract document location from keyfields');

        System.assertEquals(true, ctrl.hasPatientData, 'Should load patient data from linked Account');
    }

    @isTest
    static void testEmptyInitialization() {
        Test.setCurrentPage(Page.GeminiFileInsightsPdf);

        Test.startTest();
        GeminiFileInsightsPdfController ctrl = new GeminiFileInsightsPdfController();
        Test.stopTest();

        System.assertEquals('AI Summary', ctrl.fileTitle, 'Title should be default for blank initialization');
        System.assertEquals(false, ctrl.getHasData(), 'Should report no data');
    }
}