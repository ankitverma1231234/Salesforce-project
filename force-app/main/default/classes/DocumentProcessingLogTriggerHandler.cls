public without sharing class DocumentProcessingLogTriggerHandler {
    private static Boolean resumeBatchStarted = false;

    
    public static void handle(
        List<Document_Processing_Log__c> newList,
        Map<Id, Document_Processing_Log__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        for (Document_Processing_Log__c logRecord : newList) {
            Document_Processing_Log__c oldLog = oldMap == null ? null : oldMap.get(logRecord.Id);
            if (oldLog == null || logRecord.Content_Version_Id__c == null) {
                continue;
            }

            String nextStep = nextStepFromFlip(logRecord, oldLog);
            if (String.isBlank(nextStep)) {
                continue;
            }

            if (!canEnqueueQueueable()) {
                System.debug(
                    LoggingLevel.WARN,
                    'DocumentProcessingLogTriggerHandler skipped enqueue for log=' + logRecord.Id +
                    ', step=' + nextStep +
                    ' because this transaction has no queueable capacity left. ' +
                    'The ready flag remains true and DocumentProcessingLogRetryBatch will resume it.'
                );
                startResumeBatch();
                continue;
            }

            System.enqueueJob(new DocumentProcessingPipelineQueueable(
                nextStep,
                logRecord.Id,
                logRecord.Content_Version_Id__c
            ));
        }
    }

    private static String nextStepFromFlip(
        Document_Processing_Log__c logRecord,
        Document_Processing_Log__c oldLog
    ) {
        if (flippedTrue(logRecord.Ready_for_Attachment__c, oldLog.Ready_for_Attachment__c)) {
            return 'ATTACHMENT';
        }
        if (flippedTrue(logRecord.Ready_for_Ai_Naming__c, oldLog.Ready_for_Ai_Naming__c)) {
            return 'AI_NAMING';
        }
        if (flippedTrue(logRecord.Ready_for_Ai_Summery__c, oldLog.Ready_for_Ai_Summery__c)) {
            return 'AI_SUMMARY';
        }
        if (flippedTrue(logRecord.Ready_for_Gdrive__c, oldLog.Ready_for_Gdrive__c)) {
            return 'GDRIVE';
        }
        return null;
    }

    private static Boolean flippedTrue(Boolean newVal, Boolean oldVal) {
        return newVal == true && oldVal != true;
    }

    private static Boolean canEnqueueQueueable() {
        return Limits.getQueueableJobs() < Limits.getLimitQueueableJobs();
    }

    private static void startResumeBatch() {
        if (resumeBatchStarted || Test.isRunningTest()) {
            return;
        }

        resumeBatchStarted = true;
        Database.executeBatch(new DocumentProcessingLogRetryBatch(), 1);
    }
}