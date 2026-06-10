public without sharing class AccountFileExternalSyncService {

    private static final String OBJECT_API_NAME = 'ContentDocument';
    private static final String STORAGE_PROVIDER = 'Google Drive';
    private static final Integer FILE_SYNC_BATCH_SIZE = 100;
    private static Set<String> syncKeysQueuedInTransaction = new Set<String>();

    @TestVisible static FileSyncBatchExecutor batchExecutor = new ManagedPackageBatchExecutor();
    @TestVisible static String lastContentDocumentQuery;
    @TestVisible static Id lastJobId;

    public static SyncResult queueContentDocumentSync(List<Id> contentDocumentIds) {
        SyncResult result = new SyncResult();
        result.queued = false;
        result.failed = false;
        result.skippedDuplicate = false;
        result.contentDocumentCount = 0;

        Set<Id> uniqueDocumentIds = normalizeIds(contentDocumentIds);
        result.contentDocumentCount = uniqueDocumentIds.size();

        if (uniqueDocumentIds.isEmpty()) {
            return result;
        }

        String syncKey = buildSyncKey(uniqueDocumentIds);
        if (syncKeysQueuedInTransaction.contains(syncKey)) {
            result.skippedDuplicate = true;
            return result;
        }

        try {
            fra__File_Sync_Job__c job = new fra__File_Sync_Job__c(
                fra__Batch_Status__c = 'Queued',
                fra__Object_API_Name__c = OBJECT_API_NAME,
                fra__Sync_ContentVersion__c = true,
                fra__Sync_Attachment__c = false
            );
            insert job;

            String query = buildContentDocumentQuery(uniqueDocumentIds);
            lastContentDocumentQuery = query;
            lastJobId = job.Id;

            // Integration point with the managed package. This preserves the
            // existing FileSyncBatch framework and only scopes it to the newly
            // uploaded ContentDocument records.
            batchExecutor.execute(
                OBJECT_API_NAME,
                job.Id,
                true,
                false,
                FILE_SYNC_BATCH_SIZE,
                query,
                STORAGE_PROVIDER,
                null
            );

            syncKeysQueuedInTransaction.add(syncKey);
            result.queued = true;
            result.jobId = job.Id;
        } catch (Exception e) {
            result.failed = true;
            result.errorMessage = e.getMessage();
            System.debug(LoggingLevel.ERROR,
                'AccountFileExternalSyncService.queueContentDocumentSync failed: ' +
                e.getMessage() + '\n' + e.getStackTraceString());
        }

        return result;
    }

    @TestVisible
    private static String buildContentDocumentQuery(Set<Id> contentDocumentIds) {
        List<String> escapedIds = new List<String>();
        for (Id docId : contentDocumentIds) {
            escapedIds.add('\'' + String.escapeSingleQuotes(String.valueOf(docId)) + '\'');
        }
        escapedIds.sort();

        return 'SELECT Id FROM ContentDocument WHERE Id IN (' +
            String.join(escapedIds, ',') + ')';
    }

    private static Set<Id> normalizeIds(List<Id> contentDocumentIds) {
        Set<Id> uniqueIds = new Set<Id>();
        if (contentDocumentIds == null) {
            return uniqueIds;
        }
        for (Id docId : contentDocumentIds) {
            if (docId != null) {
                uniqueIds.add(docId);
            }
        }
        return uniqueIds;
    }

    private static String buildSyncKey(Set<Id> contentDocumentIds) {
        List<String> idStrings = new List<String>();
        for (Id docId : contentDocumentIds) {
            idStrings.add(String.valueOf(docId));
        }
        idStrings.sort();
        return String.join(idStrings, ',');
    }

    public interface FileSyncBatchExecutor {
        Id execute(
            String objectApiName,
            Id jobId,
            Boolean syncContentVersion,
            Boolean syncAttachment,
            Integer queryLimit,
            String contentDocumentQuery,
            String storageProvider,
            String parentId
        );
    }

    private class ManagedPackageBatchExecutor implements FileSyncBatchExecutor {
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
            return Database.executeBatch(
                new fra.FileSyncBatch(
                    objectApiName,
                    jobId,
                    syncContentVersion,
                    syncAttachment,
                    queryLimit,
                    contentDocumentQuery,
                    storageProvider,
                    parentId
                ),
                1
            );
        }
    }

    public class SyncResult {
        @AuraEnabled public Boolean queued;
        @AuraEnabled public Boolean failed;
        @AuraEnabled public Boolean skippedDuplicate;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Id jobId;
        @AuraEnabled public Integer contentDocumentCount;
    }

}