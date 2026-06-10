@IsTest(SeeAllData=true)
private class DocumentProcessingLogRetryBatchTest {
    @IsTest
    static void nextRetryStepCoversPriorityFallbackAndCompletedStates() {
        Id versionId = Id.valueOf('068000000000001AAA');
        System.assertEquals(null, DocumentProcessingLogRetryBatch.nextRetryStep(null));
        System.assertEquals(
            null,
            DocumentProcessingLogRetryBatch.nextRetryStep(
                new Document_Processing_Log__c()
            )
        );

        List<Document_Processing_Log__c> logs = new List<Document_Processing_Log__c>{
            new Document_Processing_Log__c(
                Content_Version_Id__c = versionId,
                Ready_for_Attachment__c = true
            ),
            new Document_Processing_Log__c(
                Content_Version_Id__c = versionId,
                Attachment_Created_On__c = System.now(),
                Ready_for_Ai_Naming__c = true
            ),
            new Document_Processing_Log__c(
                Content_Version_Id__c = versionId,
                Attachment_Created_On__c = System.now(),
                AI_Naming_Completed_On__c = System.now(),
                Ready_for_Ai_Summery__c = true
            ),
            new Document_Processing_Log__c(
                Content_Version_Id__c = versionId,
                Attachment_Created_On__c = System.now(),
                AI_Naming_Completed_On__c = System.now(),
                AI_Summary_Completed_On__c = System.now(),
                Ready_for_Gdrive__c = true
            )
        };
        List<String> expected = new List<String>{
            'ATTACHMENT', 'AI_NAMING', 'AI_SUMMARY', 'GDRIVE'
        };
        for (Integer i = 0; i < logs.size(); i++) {
            System.assertEquals(
                expected[i],
                DocumentProcessingLogRetryBatch.nextRetryStep(logs[i])
            );
        }

        Document_Processing_Log__c completed = new Document_Processing_Log__c(
            Content_Version_Id__c = versionId,
            Attachment_Created_On__c = System.now(),
            AI_Naming_Completed_On__c = System.now(),
            AI_Summary_Completed_On__c = System.now(),
            Drive_Sync_Completed_On__c = System.now(),
            Main_File_Storage_Record_Id__c = 'main',
            AI_Summary_File_Storage_Record_Id__c = 'summary'
        );
        System.assertEquals(
            null,
            DocumentProcessingLogRetryBatch.nextRetryStep(completed)
        );

        completed.AI_Summary_File_Storage_Record_Id__c = null;
        System.assertEquals(
            'GDRIVE',
            DocumentProcessingLogRetryBatch.nextRetryStep(completed)
        );
    }

    @IsTest
    static void executeUpdatesRetryCountAndHandlesEmptyAndCompletedScopes() {
        ContentVersion version = FileStorageApexTestFactory.createFile(
            getExistingAccount(),
            'Retry Batch',
            'RetryBatch.pdf',
            'content'
        );
        Document_Processing_Log__c pending =
            FileStorageApexTestFactory.createProcessingLog(version.Id, true);
        DocumentProcessingLogRetryBatch batchInstance =
            new DocumentProcessingLogRetryBatch(null, null);
        DocumentProcessingLogRetryBatch.skipEnqueueForTest = true;

        batchInstance.execute(null, new List<SObject>());
        batchInstance.execute(null, new List<SObject>{ pending });

        System.assertEquals(
            1,
            [
                SELECT Retry_Count__c
                FROM Document_Processing_Log__c
                WHERE Id = :pending.Id
            ].Retry_Count__c
        );

        Document_Processing_Log__c completed = new Document_Processing_Log__c(
            Content_Version_Id__c = String.valueOf(version.Id),
            Attachment_Created_On__c = System.now(),
            AI_Naming_Completed_On__c = System.now(),
            AI_Summary_Completed_On__c = System.now(),
            Drive_Sync_Completed_On__c = System.now(),
            Main_File_Storage_Record_Id__c = 'main',
            AI_Summary_File_Storage_Record_Id__c = 'summary'
        );
        batchInstance.execute(null, new List<SObject>{ completed });
        batchInstance.finish(null);
    }

    @IsTest
    static void startRunNowAndSchedulerEntryPointsWork() {
        ContentVersion version = FileStorageApexTestFactory.createFile(
            getExistingAccount(),
            'Retry Start',
            'RetryStart.pdf',
            'content'
        );
        FileStorageApexTestFactory.createProcessingLog(version.Id, true);
        DocumentProcessingLogRetryBatch.skipEnqueueForTest = true;

        DocumentProcessingLogRetryBatch batchInstance =
            new DocumentProcessingLogRetryBatch(3, 0);
        System.assertNotEquals(null, batchInstance.start(null));

        Test.startTest();
        Id batchJobId = DocumentProcessingLogRetryBatch.runNow(0);
        System.abortJob(batchJobId);
        Test.stopTest();

        System.assertNotEquals(null, batchJobId);
        System.assertEquals(
            'Aborted',
            [SELECT Status FROM AsyncApexJob WHERE Id = :batchJobId].Status
        );
    }

    @IsTest
    static void scheduleDailyReplacesExistingScheduleAndUsesDefaultCron() {
        DocumentProcessingLogRetryBatch.scheduleDaily('0 15 1 * * ?');
        DocumentProcessingLogRetryBatch.scheduleDaily(null);

        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Document Processing Log Daily Retry'
        ];
        System.assertEquals(1, scheduledJobs.size());
        System.assertEquals('0 0 1 * * ?', scheduledJobs[0].CronExpression);

        DocumentProcessingLogRetryBatch.abortExistingSchedules();
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = 'Document Processing Log Daily Retry'
            ]
        );
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