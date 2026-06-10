trigger FileExternalSyncEventTrigger on File_External_Sync_Event__e (after insert) {
    
    List<Id> allContentDocumentIds = new List<Id>();
    
    for (File_External_Sync_Event__e event : Trigger.new) {
        
        if (String.isBlank(event.Content_Document_Ids__c)) continue;
        
        try {
            List<Object> parsedIds = (List<Object>) JSON.deserializeUntyped(
                event.Content_Document_Ids__c
            );
            for (Object idObj : parsedIds) {
                if (idObj != null) {
                    allContentDocumentIds.add(Id.valueOf((String) idObj));
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 
                         'ERROR: Failed to parse Content_Document_Ids__c: ' + e.getMessage());
        }
    }
    
    if (allContentDocumentIds.isEmpty()) return;
    
    try {
        AccountFileExternalSyncService.SyncResult syncResult =
            AccountFileExternalSyncService.queueContentDocumentSync(allContentDocumentIds);
        
        if (syncResult.failed) {
            System.debug(LoggingLevel.ERROR, 
                         'ERROR: Google Drive Sync Failed=' + syncResult.errorMessage);
        }
        
        DateTime scheduledTime = DateTime.now().addMinutes(3);
        String cronExp = String.format(
            '0 {0} {1} {2} {3} ? {4}',
            new List<String>{
                String.valueOf(scheduledTime.minute()),
                    String.valueOf(scheduledTime.hour()),
                    String.valueOf(scheduledTime.day()),
                    String.valueOf(scheduledTime.month()),
                    String.valueOf(scheduledTime.year())
                    }
        );
        DateTime scheduledTimeDataCopy = DateTime.now().addMinutes(1);
        String cronExpDataCopy = String.format(
            '0 {0} {1} {2} {3} ? {4}',
            new List<String>{
                String.valueOf(scheduledTimeDataCopy.minute()),
                    String.valueOf(scheduledTimeDataCopy.hour()),
                    String.valueOf(scheduledTimeDataCopy.day()),
                    String.valueOf(scheduledTimeDataCopy.month()),
                    String.valueOf(scheduledTimeDataCopy.year())
                    }
        );
        String jobNameDataCopy = 'FileStorageContentVersionBackfillBatch' + DateTime.now().getTime();
        String jobName = 'FileStoragePublicUrlBackfillBatch_' + DateTime.now().getTime();
        System.schedule(jobNameDataCopy,cronExpDataCopy,new FileStorageContentVersionBackfillBatch() );
        System.schedule(
            jobName,
            cronExp,
            new FileStoragePublicUrlBackfillBatch()
        );
        
        System.debug('DEBUG: Scheduled FileStoragePublicUrlBackfillBatch at ' + scheduledTime);
        
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR,
                     'ERROR: FileExternalSyncEventTrigger failed: ' + 
                     e.getMessage() + '\n' + e.getStackTraceString());
    }
}