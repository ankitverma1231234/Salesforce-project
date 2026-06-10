@IsTest
private class FileExternalSyncEventTriggerTest {
    private class SuccessfulBatchExecutor
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
            return jobId;
        }
    }

    private class FailingBatchExecutor
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
            throw new FileExternalSyncTestException('Simulated sync failure');
        }
    }

    private class FileExternalSyncTestException extends Exception {
    }

    @IsTest
    static void validEventsQueueOneSyncAndScheduleFollowUpJobs() {
        AccountFileExternalSyncService.batchExecutor =
            new SuccessfulBatchExecutor();

        Id firstDocumentId = Id.valueOf('069000000000001AAA');
        Id secondDocumentId = Id.valueOf('069000000000002AAA');

        EventBus.publish(new List<File_External_Sync_Event__e>{
            new File_External_Sync_Event__e(
                Content_Document_Ids__c = JSON.serialize(
                    new List<Id>{ firstDocumentId }
                )
            ),
            new File_External_Sync_Event__e(
                Content_Document_Ids__c = JSON.serialize(
                    new List<Id>{ secondDocumentId, firstDocumentId }
                )
            )
        });

        Test.getEventBus().deliver();

        List<fra__File_Sync_Job__c> jobs = [
            SELECT Id, fra__Batch_Status__c, fra__Object_API_Name__c,
                   fra__Sync_ContentVersion__c, fra__Sync_Attachment__c
            FROM fra__File_Sync_Job__c
        ];
        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'FileStorageContentVersionBackfillBatch%'
               OR CronJobDetail.Name LIKE 'FileStoragePublicUrlBackfillBatch_%'
        ];
    }

    @IsTest
    static void blankAndMalformedPayloadsAreIgnored() {
        AccountFileExternalSyncService.batchExecutor =
            new SuccessfulBatchExecutor();

        EventBus.publish(new List<File_External_Sync_Event__e>{
            new File_External_Sync_Event__e(),
            new File_External_Sync_Event__e(Content_Document_Ids__c = ''),
            new File_External_Sync_Event__e(
                Content_Document_Ids__c = 'not-valid-json'
            ),
            new File_External_Sync_Event__e(
                Content_Document_Ids__c = JSON.serialize(
                    new List<String>{ null }
                )
            )
        });

        Test.getEventBus().deliver();
    }

    @IsTest
    static void serviceFailureIsHandledByTrigger() {
        AccountFileExternalSyncService.batchExecutor =
            new FailingBatchExecutor();

        EventBus.publish(
            new File_External_Sync_Event__e(
                Content_Document_Ids__c = JSON.serialize(
                    new List<Id>{ Id.valueOf('069000000000003AAA') }
                )
            )
        );

        Test.getEventBus().deliver();
    }
}