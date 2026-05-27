public with sharing class masterClassForDocumentProcessing {
    
    /*
* Main Method — Single ContentVersion Id ke liye
*/
    public static void processDocuments(
        String jsonData,
        Id contentVersionId,
        Boolean isDataComingFromMetriport
    ) {
        
        try {
            
            System.debug('=== Document Processing Started ===');
            
            if (contentVersionId == null) {
                System.debug('No ContentVersionId Received');
                return;
            }
            
            /*
* Agar data Metriport se aa raha hai
* to processing log query + checks skip kar do
*/
            if (isDataComingFromMetriport == true) {
                
                System.debug('Data Coming From Metriport - Skipping Processing Checks');
                
                // Directly trigger required process
                AttachmentService.createAttachment(jsonData, contentVersionId);
                
                // Ya agar directly AI naming chalani ho to:
                // Database.executeBatch(new AiFileNamingDailyJob(contentVersionId), 1);
                
                return;
            }
            
            // ── Query log for this ContentVersion ──
            List<Document_Processing_Log__c> processingLogs = [
                SELECT Id,
                AI_Naming_Completed_On__c,
                AI_Summary_Completed_On__c,
                Attachment_Created_On__c,
                Drive_Sync_Completed_On__c,
                Content_Version_Id__c,
                Retry_Count__c
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c = :contentVersionId
            ];
            
            System.debug('Processing ContentVersionId :: ' + contentVersionId);
            
            for (Document_Processing_Log__c logRecord : processingLogs) {
                
                // ── STEP 1: Attachment ──
                if (logRecord.Attachment_Created_On__c == null) {
                    
                    System.debug('Attachment Creation Pending');
                    AttachmentService.createAttachment(jsonData, contentVersionId);
                    
                }
                // ── STEP 2: AI Naming ──
                else if (logRecord.AI_Naming_Completed_On__c == null) {
                    
                    System.debug('AI Naming Batch Pending');
                    if (!isBatchAlreadyRunning('AiFileNamingDailyJob', contentVersionId)) {
                        Database.executeBatch(new AiFileNamingDailyJob(contentVersionId), 1);
                    }
                    
                }
                // ── STEP 3: AI Summary ──
                else if (logRecord.AI_Summary_Completed_On__c == null) {
                    
                    System.debug('AI Summary Batch Pending');
                    if (!isBatchAlreadyRunning('AiGeneratedSummaryTitleFixBatch', contentVersionId)) {
                        Database.executeBatch(
                            new GeminiFileInsightBackfillBatch(false, false,contentVersionId ),
                            1
                        );
                    }
                    
                }
                // ── STEP 4: File Sync ──
                else if (logRecord.Drive_Sync_Completed_On__c == null) {
                    
                    System.debug('File Sync Batch Pending');
                    if (!isBatchAlreadyRunning('DummyFileSyncBatch', contentVersionId)) {
                        triggerFileSyncBatch(contentVersionId);
                    }
                    
                }
                else {
                    System.debug('All Steps Already Completed For :: ' + contentVersionId);
                }
            }
            
            System.debug('=== Document Processing Completed ===');
            
        } catch (Exception ex) {
            System.debug('Error In processDocuments');
            System.debug(ex.getMessage());
            System.debug(ex.getStackTraceString());
        }
    }
    
    /*
* File Sync Batch
*/
    private static void triggerFileSyncBatch(Id contentVersionId) {
        try {
            System.debug('Triggering File Sync Batch :: ' + contentVersionId);
            // Database.executeBatch(new DummyFileSyncBatch(contentVersionId), 1);
        } catch (Exception ex) {
            System.debug('Error Triggering File Sync Batch');
            System.debug(ex.getMessage());
        }
    }
    
    /*
* Utility — Prevent Duplicate Batch Runs
*/
    private static Boolean isBatchAlreadyRunning(String batchName, Id contentVersionId) {
        return false;
    }
}