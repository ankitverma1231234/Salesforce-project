@IsTest(SeeAllData=true)
private class FraFileStorageAiInsightsControllerTest {
    @IsTest
    static void getInsightsReturnsStoredAnalysis() {
        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Controller Clinical Report',
            'ControllerClinicalReport.pdf',
            'clinical content'
        );
        FileStorageApexTestFactory.createProcessingLog(version.Id, false);
        Id attachmentId = GeminiAnalysisNoteService.upsertAnalysisNote(
            version.ContentDocumentId,
            testAccount.Id,
            createBundle(version)
        );
        fra__File_Storage__c storedFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Controller Clinical Report - AI Generated Summary',
                new Map<String, Object>{
                    'Document_Id__c' =>
                        String.valueOf(version.ContentDocumentId)
                }
            );

        FraFileStorageAiInsightsService.InsightsResponse response =
            FraFileStorageAiInsightsController.getInsights(storedFile.Id);

        System.assertEquals(true, response.hasInsights);
        System.assertEquals('READY', response.status);
        System.assertEquals(String.valueOf(attachmentId), response.attachmentId);
        System.assertEquals('Controller Saved Analysis', response.analysisTitle);
        System.assertEquals(
            'Controller summary content.',
            response.sections.get('summary')
        );
    }

    @IsTest
    static void askQuestionReturnsUnavailableWithoutStoredInsights() {
        Account testAccount = getExistingAccount();
        fra__File_Storage__c storedFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Controller File Without Insights',
                null
            );

        String answer = FraFileStorageAiInsightsController.askQuestion(
            storedFile.Id,
            'What is the status?'
        );

        System.assertEquals(
            'AI Insights not available for this file yet.',
            answer
        );
    }

    @IsTest
    static void controllerPropagatesInputValidation() {
        try {
            FraFileStorageAiInsightsController.askQuestion(null, 'Question');
            System.assert(false, 'Expected null file storage Id validation.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }

        try {
            FraFileStorageAiInsightsController.askQuestion(
                getExistingAccount().Id,
                ' '
            );
            System.assert(false, 'Expected blank question validation.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }

        FraFileStorageAiInsightsService.InsightsResponse response =
            FraFileStorageAiInsightsController.getInsights(null);
        System.assertEquals('ERROR', response.status);
    }

    private static GeminiFileInsightsController.AnalysisBundleWrapper createBundle(
        ContentVersion version
    ) {
        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = String.valueOf(version.ContentDocumentId);
        bundle.sourceLatestVersionId = String.valueOf(version.Id);
        bundle.analysisTitle = 'Controller Saved Analysis';
        bundle.generatedOn = String.valueOf(System.now());
        bundle.plainTextContext = 'Controller summary content.';
        bundle.sections = new Map<String, String>{
            'summary' => 'Controller summary content.'
        };
        return bundle;
    }

    private static Account getExistingAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
    }
}