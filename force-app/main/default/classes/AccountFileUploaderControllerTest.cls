@IsTest(SeeAllData=true)
private class AccountFileUploaderControllerTest {
    private class MockBatchExecutor
        implements AccountFileExternalSyncService.FileSyncBatchExecutor {
        public Id execute(
            String objectApiName,
            Id jobId,
            Boolean syncContentVersion,
            Boolean syncAttachment,
            Integer queryLimit,
            String contentDocumentQuery,
            String storageProvider,
            String parentId
        ) {
            System.assertEquals('ContentDocument', objectApiName);
            System.assertEquals(true, syncContentVersion);
            System.assertEquals(false, syncAttachment);
            System.assertEquals(100, queryLimit);
            System.assertEquals('Google Drive', storageProvider);
            System.assert(contentDocumentQuery.contains('ContentDocument'));
            return jobId;
        }
    }

    // ── Helper: builds a minimal uploadMetadataJson string ───────────────────
    private static String buildMetadataJson(
        String title,
        String sourceType,
        String category,
        String description,
        String serviceDateTime
    ) {
        AccountFileUploaderController.UploadMetadata meta =
            new AccountFileUploaderController.UploadMetadata();
        meta.title           = title;
        meta.sourceType      = sourceType;
        meta.category        = category;
        meta.description     = description;
        meta.serviceDateTime = serviceDateTime;
        return JSON.serialize(meta);
    }

    @IsTest
    static void confirmUploadLinksFilesCreatesLogsAndQueuesSync() {
        Account testAccount = getExistingAccount();
        ContentVersion linkedVersion = FileStorageApexTestFactory.createFile(
            testAccount,
            'Already Linked',
            'AlreadyLinked.pdf',
            'linked'
        );
        ContentVersion unlinkedVersion = new ContentVersion(
            Title        = 'Needs Link',
            PathOnClient = 'NeedsLink.pdf',
            VersionData  = Blob.valueOf('unlinked')
        );
        insert unlinkedVersion;
        unlinkedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :unlinkedVersion.Id
        ];

        configureAsyncDependencies();

        String metaJson = buildMetadataJson(
            'Test File',
            'Metriport',
            'Healthcare Documents',
            'Test description',
            null
        );

        Test.startTest();
        AccountFileUploaderController.UploadResult result =
            AccountFileUploaderController.confirmUpload(
                testAccount.Id,
                new List<Id>{
                    linkedVersion.ContentDocumentId,
                    unlinkedVersion.ContentDocumentId
                },
                metaJson
            );
        Test.stopTest();

        System.assertEquals(testAccount.Id, result.accountId);
        System.assertNotEquals(null, result.accountName);
        System.assertEquals(2, result.uploadedFiles.size());
        System.assertEquals(2, result.logsCreated);
        System.assertEquals(0, result.logsSkipped);
        System.assertEquals(false, result.logCreationFailed);
        System.assertEquals(true, result.syncQueued);
        System.assertNotEquals(null, result.syncJobId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId      = :testAccount.Id
                  AND ContentDocumentId   = :unlinkedVersion.ContentDocumentId
            ]
        );
        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c IN :new Set<String>{
                    String.valueOf(linkedVersion.Id),
                    String.valueOf(unlinkedVersion.Id)
                }
            ]
        );
    }

    @IsTest
    static void confirmUploadSkipsExistingLogAndDuplicateSync() {
        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Duplicate Upload',
            'DuplicateUpload.pdf',
            'content'
        );
        FileStorageApexTestFactory.createProcessingLog(version.Id, true);
        configureAsyncDependencies();

        String metaJson = buildMetadataJson(null, null, null, null, null);

        Test.startTest();
        AccountFileUploaderController.UploadResult first =
            AccountFileUploaderController.confirmUpload(
                testAccount.Id,
                new List<Id>{ version.ContentDocumentId },
                metaJson
            );
        AccountFileUploaderController.UploadResult second =
            AccountFileUploaderController.confirmUpload(
                testAccount.Id,
                new List<Id>{ version.ContentDocumentId },
                metaJson
            );
        Test.stopTest();

        System.assertEquals(0, first.logsCreated);
        System.assertEquals(1, first.logsSkipped);
        System.assertEquals(true, first.syncQueued);
        System.assertEquals(true, second.syncSkippedDuplicate);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c = :String.valueOf(version.Id)
            ]
        );
    }

    @IsTest
    static void confirmUploadValidatesInputsAndMissingAccount() {
        Account testAccount = getExistingAccount();
        String metaJson = buildMetadataJson(null, null, null, null, null);

        // null accountId
        assertUploadFailure(null, new List<Id>{ Id.valueOf('069000000000001AAA') }, metaJson);
        // null documentIds
        assertUploadFailure(testAccount.Id, null, metaJson);
        // empty documentIds
        assertUploadFailure(testAccount.Id, new List<Id>(), metaJson);
        // non-existent accountId
        assertUploadFailure(
            Id.valueOf('001000000000001AAA'),
            new List<Id>{ Id.valueOf('069000000000001AAA') },
            metaJson
        );
    }

    @IsTest
    static void confirmUploadAppliesMetadataToContentVersion() {
        Account testAccount = getExistingAccount();
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'Metadata Test',
            'MetadataTest.pdf',
            'content'
        );
        configureAsyncDependencies();

        String metaJson = buildMetadataJson(
            'Updated Title',
            'Metriport',
            'Healthcare Documents',
            'Updated description',
            '2026-06-01T00:00:00.000Z'
        );

        Test.startTest();
        AccountFileUploaderController.UploadResult result =
            AccountFileUploaderController.confirmUpload(
                testAccount.Id,
                new List<Id>{ version.ContentDocumentId },
                metaJson
            );
        Test.stopTest();

        System.assertEquals(1, result.uploadedFiles.size());
        System.assertEquals('Updated Title', result.uploadedFiles[0].title);

        ContentVersion updated = [
            SELECT Title, Source_Type__c, Category__c, Description
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
        System.assertEquals('Updated Title',          updated.Title);
        System.assertEquals('Metriport',              updated.Source_Type__c);
        System.assertEquals('Healthcare Documents',   updated.Category__c);
        System.assertEquals('Updated description',    updated.Description);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static void configureAsyncDependencies() {
        AccountFileExternalSyncService.batchExecutor = new MockBatchExecutor();
        FileStoragePublicUrlBackfillBatch.skipScheduledBatchExecutionForTest = true;
    }

    private static Account getExistingAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
    }

    private static void assertUploadFailure(
        Id accountId,
        List<Id> documentIds,
        String metaJson
    ) {
        try {
            AccountFileUploaderController.confirmUpload(accountId, documentIds, metaJson);
            System.assert(false, 'Expected confirmUpload to reject invalid input.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
    }
}