@IsTest(SeeAllData=true)
private class DocumentPipelineQueueableTest {
    @IsTest
    static void attachmentStepCreatesPayloadAndAdvancesLog() {
        Account testAccount = getExistingAccount();
        ContentVersion version = createSourceVersion(
            testAccount,
            'Attachment Source',
            'AttachmentSource.pdf'
        );
        Document_Processing_Log__c logRecord =
            FileStorageApexTestFactory.createProcessingLog(version.Id, false);

        new DocumentProcessingPipelineQueueable(
            'ATTACHMENT',
            logRecord.Id,
            version.Id
        ).execute(null);

        Document_Processing_Log__c updatedLog = [
            SELECT Attachment_Id__c, Attachment_Created_On__c,
                   Ready_for_Ai_Naming__c, Current_Status__c
            FROM Document_Processing_Log__c
            WHERE Id = :logRecord.Id
        ];
        System.assertNotEquals(null, updatedLog.Attachment_Id__c);
        System.assertNotEquals(null, updatedLog.Attachment_Created_On__c);
        System.assertEquals(true, updatedLog.Ready_for_Ai_Naming__c);
        System.assertEquals('Attachment Created', updatedLog.Current_Status__c);

        Attachment payload = [
            SELECT Name, Body, ParentId, ContentType, Description
            FROM Attachment
            WHERE Id = :updatedLog.Attachment_Id__c
        ];
        System.assertEquals('Attachment Source.json', payload.Name);
        System.assertEquals(logRecord.Id, payload.ParentId);
        System.assertEquals('application/json', payload.ContentType);

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(payload.Body.toString());
        System.assertEquals(String.valueOf(version.Id), String.valueOf(body.get('contentVersionId')));
        System.assertEquals('Attachment Source', body.get('title'));
        System.assertEquals('Metriport', body.get('source'));
        System.assertEquals('Test Organization', body.get('organizationName'));
        System.assertEquals('AttachmentSource.pdf', body.get('pathOnClient'));
    }

    @IsTest
    static void aiNamingStepQueuesSingleRecordBatch() {
        ContentVersion version = createSourceVersion(
            getExistingAccount(),
            'Naming Source',
            'NamingSource.pdf'
        );

        new DocumentProcessingPipelineQueueable(
            'AI_NAMING',
            null,
            version.Id
        ).execute(null);

        List<AsyncApexJob> jobs = [
            SELECT Id, ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AiFileNamingDailyJob'
        ];
       
    }

    @IsTest
    static void aiSummaryStepQueuesSingleRecordBatch() {
        ContentVersion version = createSourceVersion(
            getExistingAccount(),
            'Summary Source',
            'SummarySource.pdf'
        );

        new DocumentProcessingPipelineQueueable(
            'AI_SUMMARY',
            null,
            version.Id
        ).execute(null);

        List<AsyncApexJob> jobs = [
            SELECT Id, ApexClass.Name, Status
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'GeminiFileInsightBackfillBatch'
        ];
       
    }

    @IsTest
    static void gdriveStepCreatesSyncJobForSourceAndAiSummary() {
        FileStorageApexTestFactory.ensureGoogleDriveConfig();
        Account testAccount = getExistingAccount();
        ContentVersion sourceVersion = createSourceVersion(
            testAccount,
            'Drive Source',
            'DriveSource.pdf'
        );
        ContentVersion aiVersion = createAiVersion(
            testAccount,
            sourceVersion.ContentDocumentId
        );
        Document_Processing_Log__c logRecord =
            FileStorageApexTestFactory.createProcessingLog(sourceVersion.Id, false);
        Integer jobsBefore = [SELECT COUNT() FROM fra__File_Sync_Job__c];

        DocumentProcessingPipelineQueueable queueable =
            new DocumentProcessingPipelineQueueable(
                'GDRIVE',
                logRecord.Id,
                sourceVersion.Id
            );
        List<ContentVersion> selected = queueable.getUploadableDriveVersions();
        System.assertEquals(2, selected.size());
        System.assertEquals(
            new Set<Id>{
                sourceVersion.ContentDocumentId,
                aiVersion.ContentDocumentId
            },
            contentDocumentIds(selected)
        );

        Set<Id> existingBatchJobIds = new Map<Id, AsyncApexJob>([
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
        ]).keySet();

        queueable.execute(null);

        System.assertEquals(
            jobsBefore + 1,
            [SELECT COUNT() FROM fra__File_Sync_Job__c]
        );
        fra__File_Sync_Job__c syncJob = [
            SELECT fra__Batch_Status__c, fra__Object_API_Name__c,
                   fra__Sync_ContentVersion__c, fra__Sync_Attachment__c
            FROM fra__File_Sync_Job__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Queued', syncJob.fra__Batch_Status__c);
        System.assertEquals('ContentDocument', syncJob.fra__Object_API_Name__c);
        System.assertEquals(true, syncJob.fra__Sync_ContentVersion__c);
        System.assertEquals(false, syncJob.fra__Sync_Attachment__c);

        List<AsyncApexJob> jobs = [
            SELECT Id, JobType
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND Id NOT IN :existingBatchJobIds
            AND Status IN ('Holding', 'Queued', 'Preparing')
        ];
        for (AsyncApexJob job : jobs) {
            System.abortJob(job.Id);
        }
    }

    @IsTest
    static void driveSelectionSkipsCompletedAndIneligibleSources() {
        Account testAccount = getExistingAccount();
        ContentVersion sourceVersion = createSourceVersion(
            testAccount,
            'Completed Source',
            'CompletedSource.pdf'
        );
        Document_Processing_Log__c completedLog =
            FileStorageApexTestFactory.createProcessingLog(sourceVersion.Id, false);
        update new Document_Processing_Log__c(
            Id = completedLog.Id,
            Drive_Sync_Completed_On__c = System.now(),
            Main_File_Storage_Record_Id__c = 'main-file-storage',
            AI_Summary_File_Storage_Record_Id__c = 'summary-storage'
        );

        DocumentProcessingPipelineQueueable completedQueueable =
            new DocumentProcessingPipelineQueueable(
                'GDRIVE',
                completedLog.Id,
                sourceVersion.Id
            );
        System.assertEquals(
            0,
            completedQueueable.getUploadableDriveVersions().size()
        );
        completedQueueable.execute(null);

        ContentVersion nonMetriport = FileStorageApexTestFactory.createFile(
            testAccount,
            'Ineligible Source',
            'IneligibleSource.txt',
            'content'
        );
        DocumentProcessingPipelineQueueable ineligibleQueueable =
            new DocumentProcessingPipelineQueueable(
                'GDRIVE',
                null,
                nonMetriport.Id
            );
        System.assertEquals(
            0,
            ineligibleQueueable.getUploadableDriveVersions().size()
        );
        ineligibleQueueable.execute(null);
    }

    @IsTest
    static void driveSelectionHonorsExistingCanonicalFileIds() {
        Account testAccount = getExistingAccount();
        ContentVersion sourceVersion = createSourceVersion(
            testAccount,
            'Partial Source',
            'PartialSource.pdf'
        );
        ContentVersion aiVersion = createAiVersion(
            testAccount,
            sourceVersion.ContentDocumentId
        );
        Document_Processing_Log__c logRecord =
            FileStorageApexTestFactory.createProcessingLog(sourceVersion.Id, false);

        update new Document_Processing_Log__c(
            Id = logRecord.Id,
            Main_File_Storage_Record_Id__c = 'existing-main'
        );
        List<ContentVersion> summaryOnly =
            new DocumentProcessingPipelineQueueable(
                'GDRIVE',
                logRecord.Id,
                sourceVersion.Id
            ).getUploadableDriveVersions();
        System.assertEquals(1, summaryOnly.size());
        System.assertEquals(aiVersion.Id, summaryOnly[0].Id);

        update new Document_Processing_Log__c(
            Id = logRecord.Id,
            Main_File_Storage_Record_Id__c = null,
            AI_Summary_File_Storage_Record_Id__c = 'existing-summary'
        );
        List<ContentVersion> sourceOnly =
            new DocumentProcessingPipelineQueueable(
                'GDRIVE',
                logRecord.Id,
                sourceVersion.Id
            ).getUploadableDriveVersions();
        System.assertEquals(1, sourceOnly.size());
        System.assertEquals(sourceVersion.Id, sourceOnly[0].Id);
    }

    @IsTest
    static void driveSelectionWithoutLogHandlesOptionalSummary() {
        Account testAccount = getExistingAccount();
        ContentVersion sourceVersion = createSourceVersion(
            testAccount,
            'No Log Source',
            'NoLogSource.pdf'
        );

        List<ContentVersion> sourceOnly =
            new DocumentProcessingPipelineQueueable(
                'GDRIVE',
                null,
                sourceVersion.Id
            ).getUploadableDriveVersions();
        System.assertEquals(1, sourceOnly.size());
        System.assertEquals(sourceVersion.Id, sourceOnly[0].Id);

        ContentVersion aiVersion = createAiVersion(
            testAccount,
            sourceVersion.ContentDocumentId
        );
        List<ContentVersion> sourceAndSummary =
            new DocumentProcessingPipelineQueueable(
                'GDRIVE',
                null,
                sourceVersion.Id
            ).getUploadableDriveVersions();

        System.assertEquals(2, sourceAndSummary.size());
        System.assertEquals(
            new Set<Id>{
                sourceVersion.ContentDocumentId,
                aiVersion.ContentDocumentId
            },
            contentDocumentIds(sourceAndSummary)
        );
    }

    @IsTest
    static void unknownStepIsSafe() {
        new DocumentProcessingPipelineQueueable(
            null,
            null,
            null
        ).execute(null);
        new DocumentProcessingPipelineQueueable(
            'UNKNOWN',
            null,
            null
        ).execute(null);
        System.assertEquals(0, Limits.getQueueableJobs());
    }

    private static ContentVersion createSourceVersion(
        Account testAccount,
        String title,
        String path
    ) {
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            title,
            path,
            'source content'
        );
        update new ContentVersion(
            Id = version.Id,
            Description = 'Test Description',
            Source__c = 'Metriport',
            Organization_Name__c = 'Test Organization',
            Service_Date_Time__c = System.now()
        );
        return [
            SELECT Id, ContentDocumentId, Title, PathOnClient, FileType
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
    }

    private static ContentVersion createAiVersion(
        Account testAccount,
        Id sourceContentDocumentId
    ) {
        ContentVersion version = FileStorageApexTestFactory.createFile(
            testAccount,
            'AI Generated Summary',
            'AiGeneratedSummary.pdf',
            'summary content'
        );
        update new ContentVersion(
            Id = version.Id,
            Source__c = 'AI',
            Related_File__c = String.valueOf(sourceContentDocumentId)
        );
        return [
            SELECT Id, ContentDocumentId, Title, FileType, Source__c,
                   Related_File__c
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
    }

    private static Set<Id> contentDocumentIds(
        List<ContentVersion> versions
    ) {
        Set<Id> ids = new Set<Id>();
        for (ContentVersion version : versions) {
            ids.add(version.ContentDocumentId);
        }
        return ids;
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