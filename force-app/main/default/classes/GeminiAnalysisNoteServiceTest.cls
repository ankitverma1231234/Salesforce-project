@IsTest(SeeAllData=true)
private class GeminiAnalysisNoteServiceTest {
    private static ContentVersion createTestFile(
        Account testAccount,
        String title,
        String path,
        String content
    ) {
        return FileStorageApexTestFactory.createFile(
            testAccount,
            title,
            path,
            content
        );
    }

    @IsTest
    static void upsertAndRetrieveAnalysis() {
        Account testAccount = getExistingAccount();
        ContentVersion version = createTestFile(
            testAccount,
            'Test Note Document',
            'TestNoteDocument.pdf',
            'source'
        );
        FileStorageApexTestFactory.createProcessingLog(version.Id, false);
        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            createBundle(version, 'Stored Analysis');

        Id attachmentId = GeminiAnalysisNoteService.upsertAnalysisNote(
            version.ContentDocumentId,
            testAccount.Id,
            bundle
        );
        GeminiFileInsightsController.AnalysisBundleWrapper retrieved =
            GeminiAnalysisNoteService.getStoredAnalysis(version.ContentDocumentId);
        Attachment withBody =
            GeminiAnalysisNoteService.getStoredAnalysisAttachment(
                version.ContentDocumentId,
                true
            );
        Attachment withoutBody =
            GeminiAnalysisNoteService.getStoredAnalysisAttachment(
                version.ContentDocumentId,
                false
            );

        System.assertNotEquals(null, attachmentId);
        System.assertEquals('Stored Analysis', retrieved.analysisTitle);
        System.assertEquals(attachmentId, withBody.Id);
        System.assertNotEquals(null, withBody.Body);
        System.assertEquals(attachmentId, withoutBody.Id);
    }

    @IsTest
    static void stalenessTracksLatestContentVersion() {
        Account testAccount = getExistingAccount();
        ContentVersion firstVersion = createTestFile(
            testAccount,
            'Stale Check',
            'StaleCheck.pdf',
            'first'
        );
        GeminiAnalysisNoteService.upsertAnalysisNote(
            firstVersion.ContentDocumentId,
            testAccount.Id,
            createBundle(firstVersion, 'Fresh Analysis')
        );

        System.assertEquals(
            true,
            GeminiAnalysisNoteService.hasFreshAnalysis(
                firstVersion.ContentDocumentId
            )
        );

        ContentVersion secondVersion = new ContentVersion(
            ContentDocumentId = firstVersion.ContentDocumentId,
            Title = 'Stale Check',
            PathOnClient = 'StaleCheck.pdf',
            VersionData = Blob.valueOf('second')
        );
        insert secondVersion;

        System.assertEquals(
            true,
            GeminiAnalysisNoteService.isAnalysisStale(
                firstVersion.ContentDocumentId
            )
        );
        System.assertEquals(
            false,
            GeminiAnalysisNoteService.hasFreshAnalysis(
                firstVersion.ContentDocumentId
            )
        );
    }

    @IsTest
    static void missingAndIncompleteAnalysesAreStale() {
        Id missingDocumentId = Id.valueOf('069000000000001AAA');
        System.assertEquals(
            null,
            GeminiAnalysisNoteService.getStoredAnalysis(missingDocumentId)
        );
        System.assertEquals(
            null,
            GeminiAnalysisNoteService.getStoredAnalysisAttachment(
                missingDocumentId,
                true
            )
        );
        System.assertEquals(
            true,
            GeminiAnalysisNoteService.isAnalysisStale(missingDocumentId)
        );

        Account testAccount = getExistingAccount();
        ContentVersion version = createTestFile(
            testAccount,
            'Incomplete Analysis',
            'IncompleteAnalysis.pdf',
            'source'
        );
        GeminiFileInsightsController.AnalysisBundleWrapper incomplete =
            new GeminiFileInsightsController.AnalysisBundleWrapper();
        incomplete.sourceDocumentId = String.valueOf(version.ContentDocumentId);
        GeminiAnalysisNoteService.upsertAnalysisNote(
            version.ContentDocumentId,
            testAccount.Id,
            incomplete
        );
        System.assertEquals(
            true,
            GeminiAnalysisNoteService.isAnalysisStale(
                version.ContentDocumentId
            )
        );
    }

    @IsTest
    static void sameTitlesRemainIsolatedByDocumentId() {
        Account testAccount = getExistingAccount();
        ContentVersion first = createTestFile(
            testAccount,
            'Duplicate Title',
            'DuplicateOne.pdf',
            'first'
        );
        ContentVersion second = createTestFile(
            testAccount,
            'Duplicate Title',
            'DuplicateTwo.pdf',
            'second'
        );

        GeminiAnalysisNoteService.upsertAnalysisNote(
            first.ContentDocumentId,
            testAccount.Id,
            createBundle(first, 'First Analysis')
        );
        GeminiAnalysisNoteService.upsertAnalysisNote(
            second.ContentDocumentId,
            testAccount.Id,
            createBundle(second, 'Second Analysis')
        );

        String firstName = GeminiAnalysisNoteService.buildNoteTitle(
            first.Title,
            first.ContentDocumentId
        );
        String secondName = GeminiAnalysisNoteService.buildNoteTitle(
            second.Title,
            second.ContentDocumentId
        );
        System.assertNotEquals(firstName, secondName);
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Attachment
                WHERE Name IN :new Set<String>{ firstName, secondName }
            ]
        );
    }

    @IsTest
    static void upsertReplacesExistingAttachmentAndBodyCanRefreshInPlace() {
        Account testAccount = getExistingAccount();
        ContentVersion version = createTestFile(
            testAccount,
            'Lifecycle Document',
            'LifecycleDocument.pdf',
            'source'
        );
        FileStorageApexTestFactory.createProcessingLog(version.Id, false);

        Id firstId = GeminiAnalysisNoteService.upsertAnalysisNote(
            version.ContentDocumentId,
            testAccount.Id,
            createBundle(version, 'First Title')
        );
        GeminiFileInsightsController.AnalysisBundleWrapper replacement =
            createBundle(version, 'Replacement Title');
        Id replacementId = GeminiAnalysisNoteService.upsertAnalysisNote(
            version.ContentDocumentId,
            testAccount.Id,
            replacement
        );

        System.assertNotEquals(firstId, replacementId);
        String noteName = GeminiAnalysisNoteService.buildNoteTitle(
            version.Title,
            version.ContentDocumentId
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Attachment WHERE Name = :noteName]
        );

        replacement.analysisTitle = 'Refreshed Title';
        GeminiAnalysisNoteService.updateAnalysisNoteBody(
            replacementId,
            replacement
        );
        System.assertEquals(
            'Refreshed Title',
            GeminiAnalysisNoteService.getStoredAnalysis(
                version.ContentDocumentId
            ).analysisTitle
        );

        GeminiAnalysisNoteService.updateAnalysisNoteBody(null, replacement);
        GeminiAnalysisNoteService.updateAnalysisNoteBody(replacementId, null);
    }

    @IsTest
    static void retrievalSkipsMalformedAndMismatchedAttachments() {
        Account testAccount = getExistingAccount();
        ContentVersion version = createTestFile(
            testAccount,
            'Legacy Document',
            'LegacyDocument.pdf',
            'source'
        );
        String currentName = GeminiAnalysisNoteService.buildNoteTitle(
            version.Title,
            version.ContentDocumentId
        );
        insert new Attachment(
            ParentId = testAccount.Id,
            Name = currentName,
            Body = Blob.valueOf('{bad-json')
        );

        GeminiFileInsightsController.AnalysisBundleWrapper wrongBundle =
            createBundle(version, 'Wrong Document');
        wrongBundle.sourceDocumentId = '069000000000002AAA';
        insert new Attachment(
            ParentId = testAccount.Id,
            Name = currentName,
            Body = Blob.valueOf(JSON.serialize(wrongBundle))
        );

        GeminiFileInsightsController.AnalysisBundleWrapper legacyBundle =
            createBundle(version, 'Legacy Match');
        insert new Attachment(
            ParentId = testAccount.Id,
            Name = GeminiAnalysisNoteService.buildLegacyNoteTitle(
                version.Title,
                version.ContentDocumentId
            ),
            Body = Blob.valueOf(JSON.serialize(legacyBundle))
        );

        System.assertEquals(
            'Legacy Match',
            GeminiAnalysisNoteService.getStoredAnalysis(
                version.ContentDocumentId
            ).analysisTitle
        );
    }

    @IsTest
    static void titleAndParentHelpersCoverBoundaries() {
        Account testAccount = getExistingAccount();
        ContentVersion version = createTestFile(
            testAccount,
            'Parent Resolution',
            'ParentResolution.pdf',
            'source'
        );
        String longTitle = ''.leftPad(300, 'X');
        String noteTitle = GeminiAnalysisNoteService.buildNoteTitle(
            longTitle,
            version.ContentDocumentId
        );
        String legacyTitle = GeminiAnalysisNoteService.buildLegacyNoteTitle(
            longTitle,
            version.ContentDocumentId
        );

        System.assertEquals(255, noteTitle.length());
        System.assertEquals(255, legacyTitle.length());
        System.assert(noteTitle.endsWith('[' + version.ContentDocumentId + ']'));
        System.assertEquals(
            testAccount.Id,
            GeminiAnalysisNoteService.getParentRecordId(
                version.ContentDocumentId
            )
        );
    }

    private static GeminiFileInsightsController.AnalysisBundleWrapper createBundle(
        ContentVersion version,
        String title
    ) {
        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            new GeminiFileInsightsController.AnalysisBundleWrapper();
        bundle.sourceDocumentId = String.valueOf(version.ContentDocumentId);
        bundle.sourceLatestVersionId = String.valueOf(version.Id);
        bundle.analysisTitle = title;
        bundle.plainTextContext = 'Stored context';
        bundle.sections = new Map<String, String>{ 'summary' => 'Stored summary' };
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