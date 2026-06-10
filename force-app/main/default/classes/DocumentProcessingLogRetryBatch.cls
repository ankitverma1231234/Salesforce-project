public with sharing class DocumentProcessingLogRetryBatch
implements Schedulable, Database.Batchable<SObject>, Database.Stateful {
    
    private static final Integer BATCH_SIZE = 1;
    private static final Integer DEFAULT_MAX_RETRIES = 3;
    private static final Integer DEFAULT_MIN_AGE_MINUTES = 60;
    private static final String JOB_NAME = 'Document Processing Log Daily Retry';
    
    private Integer maxRetries;
    private Integer minAgeMinutes;
    private Integer totalChecked = 0;
    private Integer totalRetried = 0;
    private Integer totalSkipped = 0;
    
    @TestVisible
    private static Boolean skipEnqueueForTest = false;
    
    public DocumentProcessingLogRetryBatch() {
        this(DEFAULT_MAX_RETRIES, DEFAULT_MIN_AGE_MINUTES);
    }
    
    public DocumentProcessingLogRetryBatch(Integer maxRetries, Integer minAgeMinutes) {
        this.maxRetries = maxRetries == null ? DEFAULT_MAX_RETRIES : maxRetries;
        this.minAgeMinutes = minAgeMinutes == null ? DEFAULT_MIN_AGE_MINUTES : minAgeMinutes;
    }
    
    public void execute(SchedulableContext context) {
        if (isBatchRunning()) return;
        Database.executeBatch(
            new DocumentProcessingLogRetryBatch(maxRetries, minAgeMinutes),
            BATCH_SIZE
        );
    }
    
    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime cutoff = System.now().addMinutes(-minAgeMinutes);
        
        return Database.getQueryLocator([
            SELECT Id,
            Content_Version_Id__c,
            Attachment_Created_On__c,
            AI_Naming_Completed_On__c,
            AI_Summary_Completed_On__c,
            Drive_Sync_Completed_On__c,
            Main_File_Storage_Record_Id__c,
            AI_Summary_File_Storage_Record_Id__c,
            Ready_for_Attachment__c,
            Ready_for_Ai_Naming__c,
            Ready_for_Ai_Summery__c,
            Ready_for_Gdrive__c,
            Current_Status__c,
            Retry_Count__c,
            Is_Active__c,
            LastModifiedDate
            FROM Document_Processing_Log__c
            WHERE Is_Active__c = true
            AND Content_Version_Id__c != null
            AND (Retry_Count__c = null OR Retry_Count__c < :maxRetries)
            AND (
                Attachment_Created_On__c = null
                OR AI_Naming_Completed_On__c = null
                OR AI_Summary_Completed_On__c = null
                OR Drive_Sync_Completed_On__c = null
                OR Main_File_Storage_Record_Id__c = null
                OR AI_Summary_File_Storage_Record_Id__c = null
            )
            ORDER BY LastModifiedDate ASC
        ]);
    }
    
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope.isEmpty()) return;
        
        Document_Processing_Log__c logRecord = (Document_Processing_Log__c) scope[0];
        totalChecked++;
        
        String retryStep = nextRetryStep(logRecord);
        if (retryStep == null) {
            totalSkipped++;
            return;
        }
        
        Decimal retryCount = logRecord.Retry_Count__c == null ? 0 : logRecord.Retry_Count__c;
        logRecord.Retry_Count__c = retryCount + 1;
        update logRecord;
        
        if (!skipEnqueueForTest) {
            System.enqueueJob(
                new DocumentProcessingPipelineQueueable(
                    retryStep,
                    logRecord.Id,
                    logRecord.Content_Version_Id__c
                )
            );
        }
        
        totalRetried++;
    }
    
    public void finish(Database.BatchableContext context) {
        
        Database.executeBatch(
            new FileStorageContentVersionBackfillBatch(),
            200
        );
        System.debug(
            LoggingLevel.INFO,
            'DocumentProcessingLogRetryBatch completed. Checked=' + totalChecked +
            ', Retried=' + totalRetried +
            ', Skipped=' + totalSkipped
        );
    }
    
    public static void scheduleDaily(String cronExpression) {
        abortExistingSchedules();
        String cronToUse = String.isBlank(cronExpression) ? '0 0 1 * * ?' : cronExpression;
        System.schedule(JOB_NAME, cronToUse, new DocumentProcessingLogRetryBatch());
    }
    
    public static Id runNow() {
        return runNow(0);
    }
    
    public static Id runNow(Integer minAgeMinutes) {
        return Database.executeBatch(
            new DocumentProcessingLogRetryBatch(DEFAULT_MAX_RETRIES, minAgeMinutes),
            BATCH_SIZE
        );
    }
    
    public static void abortExistingSchedules() {
        for (CronTrigger triggerRecord : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
        ]) {
            System.abortJob(triggerRecord.Id);
        }
    }
    
    @TestVisible
    private static String nextRetryStep(Document_Processing_Log__c logRecord) {
        if (logRecord == null || logRecord.Content_Version_Id__c == null) {
            return null;
        }
        
        if (logRecord.Ready_for_Gdrive__c == true &&
            isDriveSyncIncomplete(logRecord)) {
                return 'GDRIVE';
            }
        
        if (logRecord.Ready_for_Ai_Summery__c == true &&
            logRecord.AI_Summary_Completed_On__c == null) {
                return 'AI_SUMMARY';
            }
        
        if (logRecord.Ready_for_Ai_Naming__c == true &&
            logRecord.AI_Naming_Completed_On__c == null) {
                return 'AI_NAMING';
            }
        
        if (logRecord.Ready_for_Attachment__c == true &&
            logRecord.Attachment_Created_On__c == null) {
                return 'ATTACHMENT';
            }
        
        if (logRecord.Attachment_Created_On__c == null) return 'ATTACHMENT';
        if (logRecord.AI_Naming_Completed_On__c == null) return 'AI_NAMING';
        if (logRecord.AI_Summary_Completed_On__c == null) return 'AI_SUMMARY';
        if (isDriveSyncIncomplete(logRecord)) return 'GDRIVE';
        
        return null;
    }
    
    private static Boolean isDriveSyncIncomplete(Document_Processing_Log__c logRecord) {
        return logRecord.Drive_Sync_Completed_On__c == null
            || String.isBlank(logRecord.Main_File_Storage_Record_Id__c)
            || String.isBlank(logRecord.AI_Summary_File_Storage_Record_Id__c);
    }
    
    private static Boolean isBatchRunning() {
        return ![
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'DocumentProcessingLogRetryBatch'
            AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            LIMIT 1
        ].isEmpty();
    }
}