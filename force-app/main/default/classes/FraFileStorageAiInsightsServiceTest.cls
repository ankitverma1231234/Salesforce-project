@IsTest(SeeAllData=true)
private class FraFileStorageAiInsightsServiceTest {
    private class GeminiMock implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;

        GeminiMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assert(request.getBody().contains('Saved AI Analytics'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(responseBody);
            return response;
        }
    }

    @IsTest
    static void getInsightsLoadsStoredAnalysisByDocumentId() {
        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Clinical Report',
            'ClinicalReport.pdf',
            'clinical content'
        );
        update new ContentVersion(
            Id = version.Id,
            Organization_Name__c = 'Example Health'
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
                'Clinical Report - AI Generated Summary',
                new Map<String, Object>{
                    'Document_Id__c' => String.valueOf(version.ContentDocumentId),
                    'fra__Uploaded_Drive__c' => 'Google Drive'
                }
            );

        FraFileStorageAiInsightsService.InsightsResponse response =
            FraFileStorageAiInsightsService.getInsights(storedFile.Id);

      
    }

    @IsTest
    static void getInsightsResolvesLegacyNameAndMissingAttachment() {
        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Legacy Report',
            'Legacy Report.pdf',
            'legacy content'
        );
        fra__File_Storage__c storedFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Legacy Report.pdf - AI Generated Summary',
                null
            );

        FraFileStorageAiInsightsService.InsightsResponse response =
            FraFileStorageAiInsightsService.getInsights(storedFile.Id);

        System.assertEquals('NO_ATTACHMENT', response.status);
        System.assertEquals(false, response.hasInsights);
        System.assertEquals(
            String.valueOf(version.ContentDocumentId),
            response.contentDocumentId
        );
    }

    @IsTest
    static void getInsightsHandlesInvalidMissingAndMalformedData() {
        Account testAccount = getExistingAccount();
        System.assertEquals(
            'ERROR',
            FraFileStorageAiInsightsService.getInsights(null).status
        );

        fra__File_Storage__c invalidDocument =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Invalid Document',
                new Map<String, Object>{
                    'Document_Id__c' => 'not-a-salesforce-id'
                }
            );
        System.assertEquals(
            'NO_CONTENT_DOCUMENT',
            FraFileStorageAiInsightsService.getInsights(invalidDocument.Id).status
        );

        fra__File_Storage__c missingOriginal =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                ' - AI Generated Summary',
                null
            );
        System.assertEquals(
            'NO_CONTENT_DOCUMENT',
            FraFileStorageAiInsightsService.getInsights(missingOriginal.Id).status
        );

        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Malformed Report',
            'MalformedReport.pdf',
            'content'
        );
        Document_Processing_Log__c logRecord =
            FileStorageApexTestFactory.createProcessingLog(version.Id, false);
        insert new Attachment(
            ParentId = logRecord.Id,
            Name = GeminiAnalysisNoteService.buildNoteTitle(
                version.Title,
                version.ContentDocumentId
            ),
            Body = Blob.valueOf('{not-json'),
            ContentType = 'application/json'
        );
        fra__File_Storage__c malformedStorage =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Malformed Report',
                new Map<String, Object>{
                    'Document_Id__c' => String.valueOf(version.ContentDocumentId)
                }
            );
        FraFileStorageAiInsightsService.InsightsResponse malformedResponse =
            FraFileStorageAiInsightsService.getInsights(malformedStorage.Id);
        System.assertEquals('PARSE_ERROR', malformedResponse.status);
        System.assertEquals(false, malformedResponse.hasInsights);

        fra__File_Storage__c deletedStorage =
            FileStorageApexTestFactory.createFileStorage(testAccount, 'Deleted', null);
        Id deletedId = deletedStorage.Id;
        delete deletedStorage;
        System.assertEquals(
            'ERROR',
            FraFileStorageAiInsightsService.getInsights(deletedId).status
        );
    }

    @IsTest
    static void askQuestionCallsGeminiAndHandlesUnavailableInsights() {
        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Question Report',
            'QuestionReport.pdf',
            'content'
        );
        FileStorageApexTestFactory.createProcessingLog(version.Id, false);
        GeminiAnalysisNoteService.upsertAnalysisNote(
            version.ContentDocumentId,
            testAccount.Id,
            createBundle(version)
        );
        fra__File_Storage__c storedFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Question Report',
                new Map<String, Object>{
                    'Document_Id__c' => String.valueOf(version.ContentDocumentId)
                }
            );
        FileStorageApexTestFactory.ensureGeminiSettings();
        Test.setMock(
            HttpCalloutMock.class,
            new GeminiMock(
                200,
                '{"candidates":[{"content":{"parts":[{"text":"The patient is stable."}]}}]}'
            )
        );

        Test.startTest();
        String answer = FraFileStorageAiInsightsService.askQuestion(
            storedFile.Id,
            'What is the status?'
        );
        Test.stopTest();

        System.assertEquals('The patient is stable.', answer);

        fra__File_Storage__c noInsights =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'No Insights',
                null
            );
        System.assertEquals(
            'AI Insights not available for this file yet.',
            FraFileStorageAiInsightsService.askQuestion(noInsights.Id, 'Status?')
        );
    }

    @IsTest
    static void askQuestionValidatesInputAndApiErrors() {
        assertQuestionFailure(null, 'Question');
        assertQuestionFailure(getExistingAccount().Id, ' ');

        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Error Report',
            'ErrorReport.pdf',
            'content'
        );
        FileStorageApexTestFactory.createProcessingLog(version.Id, false);
        GeminiAnalysisNoteService.upsertAnalysisNote(
            version.ContentDocumentId,
            testAccount.Id,
            createBundle(version)
        );
        fra__File_Storage__c storedFile =
            FileStorageApexTestFactory.createFileStorage(
                testAccount,
                'Error Report',
                new Map<String, Object>{
                    'Document_Id__c' => String.valueOf(version.ContentDocumentId)
                }
            );
        FileStorageApexTestFactory.ensureGeminiSettings();
        Test.setMock(
            HttpCalloutMock.class,
            new GeminiMock(500, '{"error":"unavailable"}')
        );

        Test.startTest();
        assertQuestionFailure(storedFile.Id, 'What happened?');
        Test.stopTest();
    }

    @IsTest
    static void getInsightsParsesStructuredCollectionsAndDefaultsTitle() {
        Account testAccount = getExistingAccount();
        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sections = new Map<String, String>{
            'summary' => 'Structured summary'
        };

        GeminiFileInsightsController.TagGroupWrapper tagGroup =
            new GeminiFileInsightsController.TagGroupWrapper();
        tagGroup.category = 'Clinical';
        tagGroup.tags = new List<String>{ 'Diabetes', '', 'Hypertension' };
        bundle.tagGroups =
            new List<GeminiFileInsightsController.TagGroupWrapper>{ tagGroup };

        GeminiFileInsightsController.KeyFieldWrapper keyField =
            new GeminiFileInsightsController.KeyFieldWrapper();
        keyField.groupName = 'Patient Demographics';
        keyField.label = 'Status';
        keyField.value = 'Stable';
        bundle.keyFields =
            new List<GeminiFileInsightsController.KeyFieldWrapper>{ keyField };

        fra__File_Storage__c storedFile = createStoredAnalysis(
            testAccount,
            'Structured Report',
            bundle
        );

        FraFileStorageAiInsightsService.InsightsResponse response =
            FraFileStorageAiInsightsService.getInsights(storedFile.Id);

        System.assertEquals('READY', response.status);
        System.assertEquals('Saved AI Analysis', response.analysisTitle);
        System.assertEquals(1, response.tagGroups.size());
        System.assertEquals(2, response.tagGroups[0].tags.size());
        System.assertEquals('Diabetes', response.tagGroups[0].tags[0]);
        System.assertEquals(1, response.keyFields.size());
        System.assertEquals('Stable', response.keyFields[0].value);
    }

    @IsTest
    static void getInsightsMarksEmptyAnalysisAsParseError() {
        Account testAccount = getExistingAccount();
        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sections = new Map<String, String>();
        bundle.tagGroups =
            new List<GeminiFileInsightsController.TagGroupWrapper>();
        bundle.keyFields =
            new List<GeminiFileInsightsController.KeyFieldWrapper>();

        fra__File_Storage__c storedFile = createStoredAnalysis(
            testAccount,
            'Empty Analysis Report',
            bundle
        );

        FraFileStorageAiInsightsService.InsightsResponse response =
            FraFileStorageAiInsightsService.getInsights(storedFile.Id);

        System.assertEquals('PARSE_ERROR', response.status);
        System.assertEquals(false, response.hasInsights);
        System.assertEquals('Saved AI Analysis', response.analysisTitle);
    }

    @IsTest
    static void askQuestionBuildsFallbackContextAndParsesLegacyText() {
        Account testAccount = getExistingAccount();
        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sections = new Map<String, String>{
            'summary' => '<p>Patient is <strong>stable</strong>.</p>',
            'allergies' => 'Not documented.'
        };

        GeminiFileInsightsController.KeyFieldWrapper includedField =
            new GeminiFileInsightsController.KeyFieldWrapper();
        includedField.groupName = 'Clinical Summary';
        includedField.label = 'Disposition';
        includedField.value = 'Home';
        GeminiFileInsightsController.KeyFieldWrapper placeholderField =
            new GeminiFileInsightsController.KeyFieldWrapper();
        placeholderField.groupName = 'Clinical Summary';
        placeholderField.label = 'Risk';
        placeholderField.value = 'N/A';
        bundle.keyFields =
            new List<GeminiFileInsightsController.KeyFieldWrapper>{
                includedField,
                placeholderField
            };

        fra__File_Storage__c storedFile = createStoredAnalysis(
            testAccount,
            'Fallback Context Report',
            bundle
        );
        FileStorageApexTestFactory.ensureGeminiSettings();
        Test.setMock(
            HttpCalloutMock.class,
            new GeminiMock(
                200,
                '{"candidates":[{"content":{"text":"Legacy text answer"}}]}'
            )
        );

        Test.startTest();
        String answer = FraFileStorageAiInsightsService.askQuestion(
            storedFile.Id,
            'Where was the patient discharged?'
        );
        Test.stopTest();

        System.assertEquals('Legacy text answer', answer);
    }

    @IsTest
    static void askQuestionHandlesEmptyCandidateResponse() {
        Account testAccount = getExistingAccount();
        fra__File_Storage__c emptyCandidateFile = createStoredAnalysis(
            testAccount,
            'Empty Candidate Report',
            createBundleWithoutIds()
        );
        FileStorageApexTestFactory.ensureGeminiSettings();
        Test.setMock(
            HttpCalloutMock.class,
            new GeminiMock(200, '{"candidates":[]}')
        );

        Test.startTest();
        String emptyCandidateAnswer =
            FraFileStorageAiInsightsService.askQuestion(
                emptyCandidateFile.Id,
                'Status?'
            );
        Test.stopTest();
        System.assertEquals(
            'No response generated by Gemini.',
            emptyCandidateAnswer
        );
    }

    @IsTest
    static void askQuestionHandlesUnparseableResponse() {
        Account testAccount = getExistingAccount();
        fra__File_Storage__c invalidContentFile = createStoredAnalysis(
            testAccount,
            'Invalid Content Report',
            createBundleWithoutIds()
        );
        FileStorageApexTestFactory.ensureGeminiSettings();
        Test.setMock(
            HttpCalloutMock.class,
            new GeminiMock(200, '{"candidates":[{"content":"invalid"}]}')
        );

        Test.startTest();
        String invalidContentAnswer =
            FraFileStorageAiInsightsService.askQuestion(
                invalidContentFile.Id,
                'Status?'
            );
        Test.stopTest();
        System.assertEquals(
            'Unable to parse Gemini response.',
            invalidContentAnswer
        );
    }

    @IsTest
    static void extractOriginalFileNameHandlesAllForms() {
        System.assertEquals(
            'Report.pdf',
            FraFileStorageAiInsightsService.extractOriginalFileName(
                ' Report.pdf - AI Generated Summary '
            )
        );
        System.assertEquals(
            'Report.pdf',
            FraFileStorageAiInsightsService.extractOriginalFileName(' Report.pdf ')
        );
        System.assertEquals(
            null,
            FraFileStorageAiInsightsService.extractOriginalFileName(null)
        );
    }

    private static GeminiFileInsightsController.AnalysisBundleWrapper createBundle(
        ContentVersion version
    ) {
        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = String.valueOf(version.ContentDocumentId);
        bundle.sourceLatestVersionId = String.valueOf(version.Id);
        bundle.analysisTitle = 'Saved Clinical Analysis';
        bundle.generatedOn = String.valueOf(System.now());
        bundle.plainTextContext = 'Patient is stable.';
        bundle.sections = new Map<String, String>{
            'summary' => 'Patient is stable.',
            'assessment' => '<p>No acute issue.</p>'
        };
        return bundle;
    }

    private static GeminiFileInsightsController.AnalysisBundleWrapper
        createBundleWithoutIds() {
        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.analysisTitle = 'Question Analysis';
        bundle.plainTextContext = 'Patient is stable.';
        bundle.sections = new Map<String, String>{
            'summary' => 'Patient is stable.'
        };
        return bundle;
    }

    private static fra__File_Storage__c createStoredAnalysis(
        Account testAccount,
        String title,
        GeminiFileInsightsController.AnalysisBundleWrapper bundle
    ) {
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            title,
            title.replace(' ', '') + '.pdf',
            'content'
        );
        bundle.sourceDocumentId = String.valueOf(version.ContentDocumentId);
        bundle.sourceLatestVersionId = String.valueOf(version.Id);
        FileStorageApexTestFactory.createProcessingLog(version.Id, false);
        GeminiAnalysisNoteService.upsertAnalysisNote(
            version.ContentDocumentId,
            testAccount.Id,
            bundle
        );
        return FileStorageApexTestFactory.createFileStorage(
            testAccount,
            title,
            new Map<String, Object>{
                'Document_Id__c' => String.valueOf(version.ContentDocumentId)
            }
        );
    }

    private static void assertQuestionFailure(Id storedFileId, String question) {
        try {
            FraFileStorageAiInsightsService.askQuestion(storedFileId, question);
            System.assert(false, 'Expected AuraHandledException.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
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