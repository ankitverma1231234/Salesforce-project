public without sharing class FileStoragePublicUrlTriggerHandler {
    @TestVisible
    private static Boolean isRunning = false;
    @TestVisible
    private static Boolean forceBackfillFallback = false;
    @TestVisible
    private static Id lastFallbackBatchJobId;

    public static void handleAfterInsert(List<fra__File_Storage__c> newRecords) {
        System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlTriggerHandler.handleAfterInsert started. Size=' + (newRecords == null ? 0 : newRecords.size()));

        if (isRunning) {
            System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlTriggerHandler skipped because recursion guard is active.');
            return;
        }
        if (newRecords == null || newRecords.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlTriggerHandler skipped because there are no records.');
            return;
        }

        isRunning = true;
        try {
            Set<Id> fileStorageIds = new Set<Id>();
            Map<String, Schema.SObjectField> fields = fra__File_Storage__c.SObjectType.getDescribe().fields.getMap();
            Boolean hasFileIdField = fields.containsKey('fra__File_Id__c');
            Boolean hasPublicUrlField = fields.containsKey('fra__File_Public_Url__c');

            if (!hasFileIdField || !hasPublicUrlField) {
                System.debug(LoggingLevel.WARN, 'FileStoragePublicUrlTriggerHandler skipped. Missing fields. hasFileIdField=' + hasFileIdField + ', hasPublicUrlField=' + hasPublicUrlField);
                return;
            }

            for (fra__File_Storage__c record : newRecords) {
                String fileId = (String) record.get('fra__File_Id__c');
                String publicUrl = (String) record.get('fra__File_Public_Url__c');

                if (String.isBlank(fileId)) {
                    System.debug(LoggingLevel.DEBUG, 'Skipping File Storage record with blank Google Drive file id. Id=' + record.Id);
                    continue;
                }
                if (String.isNotBlank(publicUrl)) {
                    System.debug(LoggingLevel.DEBUG, 'Skipping File Storage record because public URL is already populated. Id=' + record.Id);
                    continue;
                }

                fileStorageIds.add(record.Id);
            }

            if (fileStorageIds.isEmpty()) {
                System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlTriggerHandler found no eligible records.');
                return;
            }
            if (!FileStoragePublicUrlQueueable.hasActiveGoogleDriveConfiguration()) {
                System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlTriggerHandler skipped because active Google Drive configuration was not found.');
                return;
            }

            System.debug(LoggingLevel.DEBUG, 'Enqueuing FileStoragePublicUrlQueueable for records=' + fileStorageIds);
            enqueuePublicUrlJob(fileStorageIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'FileStoragePublicUrlTriggerHandler failed: ' + ex.getMessage() + '\n' + ex.getStackTraceString());
        } finally {
            isRunning = false;
        }
    }

    private static void enqueuePublicUrlJob(Set<Id> fileStorageIds) {
        if (!forceBackfillFallback && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new FileStoragePublicUrlQueueable(fileStorageIds));
            return;
        }

        System.debug(
            LoggingLevel.WARN,
            'Queueable limit already reached. Starting FileStoragePublicUrlBackfillBatch fallback for records=' + fileStorageIds
        );
        startBackfillBatchIfNeeded();
    }

    private static void startBackfillBatchIfNeeded() {
        if (isBackfillBatchAlreadyActive()) {
            System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlBackfillBatch fallback skipped because an active job already exists.');
            return;
        }

        lastFallbackBatchJobId = Database.executeBatch(
            new FileStoragePublicUrlBackfillBatch(),
            FileStoragePublicUrlBackfillBatch.DEFAULT_BATCH_SIZE
        );
        System.debug(LoggingLevel.DEBUG, 'Started FileStoragePublicUrlBackfillBatch fallback. JobId=' + lastFallbackBatchJobId);
    }

    private static Boolean isBackfillBatchAlreadyActive() {
        return ![
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'FileStoragePublicUrlBackfillBatch'
            AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            LIMIT 1
        ].isEmpty();
    }
}