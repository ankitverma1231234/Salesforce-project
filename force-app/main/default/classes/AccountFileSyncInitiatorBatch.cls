public without sharing class AccountFileSyncInitiatorBatch
implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
    
    public static final Integer DEFAULT_ACCOUNT_BATCH_SIZE = 100;
    
    @TestVisible private Integer totalAccountsProcessed = 0;
    @TestVisible private Integer totalContentVersionsFound = 0;
    @TestVisible private Integer totalExistingFileStorageRecords = 0;
    @TestVisible private Integer totalUnsyncedFiles = 0;
    @TestVisible private Integer totalSyncJobsCreated = 0;
    @TestVisible private Integer totalFileSyncBatchExecutions = 0;
    @TestVisible private Map<Id, Id> candidateVersionToDocument = new Map<Id, Id>();
    @TestVisible private static FileSyncExecutor syncExecutor =
        new ManagedFileSyncExecutor();
    
    public Database.QueryLocator start(Database.BatchableContext context) {
        // Account has no standard active flag. QueryLocator naturally excludes
        // deleted records, so all current Accounts participate.
        return Database.getQueryLocator([
            SELECT Id
            FROM Account 
        ]);
    }
    
    public void execute(
        Database.BatchableContext context,
        List<Account> scope
    ) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        
        Set<Id> accountIds = new Map<Id, Account>(scope).keySet();
        totalAccountsProcessed += accountIds.size();
        
        Set<Id> linkedDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :accountIds
        ]) {
            linkedDocumentIds.add(link.ContentDocumentId);
        }
        
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, FirstPublishLocationId,
            Source_Type__c, CreatedDate
            FROM ContentVersion
            WHERE IsLatest = true
            //changed for fiilter non naming and non summary 
            AND (
                (Source_Type__c = 'Metriport'
                 AND Is_AI_Summary_Generated__c = true
                 AND AI_Name_Generated__c = true)                
                OR                
                (Source_Type__c = 'AI')
            )
            AND (
                FirstPublishLocationId IN :accountIds
                OR ContentDocumentId IN :linkedDocumentIds
            )
            ORDER BY CreatedDate DESC
        ];
        totalContentVersionsFound += versions.size();
        
        List<ContentVersion> unsyncedVersions =
            AccountFileExternalSyncService.filterUnsyncedVersions(versions);
        totalExistingFileStorageRecords +=
            versions.size() - unsyncedVersions.size();
        
        for (ContentVersion version : unsyncedVersions) {
            if (version.ContentDocumentId != null) {
                candidateVersionToDocument.put(
                    version.Id,
                    version.ContentDocumentId
                );
            }
        }
        totalUnsyncedFiles = candidateVersionToDocument.size();
    }
    
    public void finish(Database.BatchableContext context) {
        if (candidateVersionToDocument.isEmpty()) {
            System.debug('No new files found for Google Drive upload.');
            logTotals();
            return;
        }
        
        Set<String> candidateVersionIds = new Set<String>();
        for (Id versionId : candidateVersionToDocument.keySet()) {
            candidateVersionIds.add(String.valueOf(versionId));
        }
        
        Set<String> syncedVersionIds = new Set<String>();
        for (fra__File_Storage__c fileStorage : [
            SELECT fra__Internal_File_Id__c
            FROM fra__File_Storage__c
            WHERE fra__Internal_File_Id__c IN :candidateVersionIds
        ]) {
            if (String.isNotBlank(fileStorage.fra__Internal_File_Id__c)) {
                syncedVersionIds.add(fileStorage.fra__Internal_File_Id__c);
            }
        }
        
        Set<Id> unsyncedDocumentIds = new Set<Id>();
        for (Id versionId : candidateVersionToDocument.keySet()) {
            if (!syncedVersionIds.contains(String.valueOf(versionId))) {
                unsyncedDocumentIds.add(
                    candidateVersionToDocument.get(versionId)
                );
            }
        }
        
        totalExistingFileStorageRecords += syncedVersionIds.size();
        totalUnsyncedFiles = unsyncedDocumentIds.size();
        
        if (unsyncedDocumentIds.isEmpty()) {
            System.debug('No new files found for Google Drive upload.');
            logTotals();
            return;
        }
        
        fra__File_Sync_Job__c job = new fra__File_Sync_Job__c(
            fra__Batch_Status__c = 'Queued',
            fra__Object_API_Name__c = 'ContentDocument',
            fra__Sync_ContentVersion__c = true,
            fra__Sync_Attachment__c = false
        );
        insert job;
        totalSyncJobsCreated++;
        
        String contentDocumentQuery =
            buildContentDocumentQuery(unsyncedDocumentIds);
        List<AsyncApexJob> runningJobs = [
            SELECT Id, Status, ApexClass.Name
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'FileSyncBatch'
            AND Status IN ('Preparing', 'Processing', 'Queued', 'Holding')
            LIMIT 1
        ];
        
        if (!runningJobs.isEmpty()) {
            System.debug(
                'fra.FileSyncBatch is already running or queued. Skipping execution.'
            );
            
            logTotals();
            return;
        }
        
        syncExecutor.execute(job.Id, contentDocumentQuery);
        totalFileSyncBatchExecutions++;
        logTotals();
    }
    
    public void execute(SchedulableContext context) {
        Database.executeBatch(
            new AccountFileSyncInitiatorBatch(),
            DEFAULT_ACCOUNT_BATCH_SIZE
        );
    }
    
    @TestVisible
    private static String buildContentDocumentQuery(Set<Id> documentIds) {
        List<String> quotedIds = new List<String>();
        for (Id documentId : documentIds) {
            quotedIds.add(
                '\'' +
                String.escapeSingleQuotes(String.valueOf(documentId)) +
                '\''
            );
        }
        quotedIds.sort();
        return 'SELECT Id FROM ContentDocument WHERE Id IN (' +
            String.join(quotedIds, ',') +
            ')';
    }
    
    private void logTotals() {
        System.debug('Total Accounts Processed: ' + totalAccountsProcessed);
        System.debug(
            'Total ContentVersions Found: ' + totalContentVersionsFound
        );
        System.debug(
            'Total Existing File Storage Records: ' +
            totalExistingFileStorageRecords
        );
        System.debug('Total Unsynced Files: ' + totalUnsyncedFiles);
        System.debug('Total Sync Jobs Created: ' + totalSyncJobsCreated);
        System.debug(
            'Total FileSyncBatch Executions: ' +
            totalFileSyncBatchExecutions
        );
    }
    
    public interface FileSyncExecutor {
        Id execute(Id jobId, String contentDocumentQuery);
    }
    
    private class ManagedFileSyncExecutor implements FileSyncExecutor {
        public Id execute(Id jobId, String contentDocumentQuery) {
            return Database.executeBatch(
                new fra.FileSyncBatch(
                    'ContentDocument',
                    jobId,
                    true,
                    false,
                    100,
                    contentDocumentQuery,
                    'Google Drive',
                    null
                ),
                1
            );
        }
    }
}