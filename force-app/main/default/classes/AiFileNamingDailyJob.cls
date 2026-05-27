/**
* Enterprise-grade Apex Batch Class for AI-based file name generation.
*
* Processes ContentVersion records sourced from Metriport that have not yet
* been AI-named. For each eligible record, makes a Gemini API callout via
* AiFileNamingCalloutService and updates the record on success.
*
* Design principles:
*  - Database.Stateful to track metrics across batches
*  - Database.AllowsCallouts for Gemini API integration
*  - Individual record processing: one failure never blocks others
*  - Comprehensive logging via AiFileNamingLogger + AI_File_Naming_Log__c
*  - Batch size of 1 to stay within callout governor limits per execute
*
* Scheduling:
*   AiFileNamingDailyJob.scheduleDaily(null);           // default 2 AM
*   AiFileNamingDailyJob.scheduleDaily('0 0 3 * * ?');  // custom cron
*
* Manual trigger (single record):
*   AiFileNamingDailyJob.executeForContentVersion('068xxxxxxxxxxxxxxx');
*
* Manual trigger (all records):
*   AiFileNamingDailyJob.executeForContentVersion(null);
*/
public with sharing class AiFileNamingDailyJob
implements Schedulable, Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    
    private static final Integer BATCH_SIZE = 1;
    
    // When set, restricts processing to a single ContentVersion record
    // When null, processes all eligible records (scheduler flow)
    private Id contentVersionId;
    
    // Stateful counters for the finish() summary
    private Integer totalProcessed = 0;
    private Integer totalSuccess   = 0;
    private Integer totalFailed    = 0;
    private Integer totalSkipped   = 0;
    
    // ──────────────────────────────────────────────
    // Constructors
    // ──────────────────────────────────────────────
    
    /**
* Default constructor — used by the scheduler flow.
* Processes all eligible ContentVersion records.
*/
    public AiFileNamingDailyJob() {
        this.contentVersionId = null;
    }
    
    /**
* Flexible constructor — pass a specific Id for single-record processing,
* or null to fall back to the full scheduler flow.
*
* @param contentVersionId  Specific ContentVersion Id, or null for bulk run.
*/
    public AiFileNamingDailyJob(Id contentVersionId) {
        this.contentVersionId = contentVersionId;
    }
    
    // ──────────────────────────────────────────────
    // Schedulable
    // ──────────────────────────────────────────────
    
    public void execute(SchedulableContext context) {
        Database.executeBatch(new AiFileNamingDailyJob(), BATCH_SIZE);
    }
    
    public static void scheduleDaily(String cronExpression) {
        String cronToUse = String.isBlank(cronExpression) ? '0 0 2 * * ?' : cronExpression;
        System.schedule('AI File Naming Daily Job', cronToUse, new AiFileNamingDailyJob());
    }
    
    // ──────────────────────────────────────────────
    // Public static — manual trigger entry point
    // ──────────────────────────────────────────────
    
    /**
* Kicks off an explicit batch run.
* Pass a ContentVersion Id for single-record processing,
* or null to process all eligible records.
*
* Usage:
*   AiFileNamingDailyJob.executeForContentVersion('068xxxxxxxxxxxxxxx'); // single
*   AiFileNamingDailyJob.executeForContentVersion(null);                 // all
*
* @param contentVersionId  Id of the ContentVersion to process, or null for bulk.
* @return                  The batch job Id.
*/
    public static Id executeForContentVersion(Id contentVersionId) {
        return Database.executeBatch(new AiFileNamingDailyJob(contentVersionId), BATCH_SIZE);
    }
    
    // ──────────────────────────────────────────────
    // Batchable — start
    // ──────────────────────────────────────────────
    
    public Database.QueryLocator start(Database.BatchableContext context) {
        if (contentVersionId != null) {
            // ── Manual trigger: scope to the single requested record ──
            return Database.getQueryLocator([
                SELECT Id,
                ContentDocumentId,
                VersionData,
                Title,
                FileType,
                CreatedDate,
                AI_Generated_File_Name__c,
                AI_Name_Generated__c,
                Source__c
                FROM   ContentVersion
                WHERE  Id       = :contentVersionId
                AND    IsLatest = true
                AND    FileType != 'TIF'
            ]);
        }
        
        // ── Scheduler / bulk flow: original query unchanged ──
        return Database.getQueryLocator(
            'SELECT Id,ContentDocumentId,VersionData,Title,FileType,CreatedDate,'
            + 'AI_Generated_File_Name__c,AI_Name_Generated__c,Source__c '
            + 'FROM ContentVersion '
            + 'WHERE IsLatest = true '
            + 'AND Source__c = \'Metriport\' '
            + 'AND AI_Name_Generated__c = false '
            + 'AND (AI_Generated_File_Name__c = null OR AI_Generated_File_Name__c = \'\') '
            + 'AND FileType != \'TIF\' '
            + 'AND FirstPublishLocationId IN (SELECT Id FROM Account)'
        );
    }
    
    // ──────────────────────────────────────────────
    // Batchable — execute (one record per batch)
    // ──────────────────────────────────────────────
    
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope.isEmpty()) {
            return;
        }
        
        List<AI_File_Naming_Rule__c> rules = getActiveRules();
        if (rules.isEmpty()) {
            totalSkipped += scope.size();
            return;
        }
        
        String jobId = context != null ? String.valueOf(context.getJobId()) : null;
        AiFileNamingLogger logger = new AiFileNamingLogger(jobId);
        
        // Collect ContentDocumentIds to resolve linked Accounts
        Map<Id, ContentVersion> docToVersion = new Map<Id, ContentVersion>();
        Set<Id> contentDocumentIds = new Set<Id>();
        for (SObject item : scope) {
            ContentVersion cv = (ContentVersion) item;
            docToVersion.put(cv.ContentDocumentId, cv);
            contentDocumentIds.add(cv.ContentDocumentId);
        }
        
        // Resolve ContentDocument → Account via ContentDocumentLink
        Map<Id, Id> docToAccountId = resolveLinkedAccounts(contentDocumentIds);
        if (docToAccountId.isEmpty()) {
            totalSkipped += scope.size();
            return;
        }
        
        Map<Id, Account> accounts = new Map<Id, Account>([
            SELECT Id, Name
            FROM Account
            WHERE Id IN :docToAccountId.values()
        ]);
        
        // Process each record individually
        List<ContentVersion> updates = new List<ContentVersion>();
        for (Id contentDocumentId : docToVersion.keySet()) {
            ContentVersion cv = docToVersion.get(contentDocumentId);
            Id accountId = docToAccountId.get(contentDocumentId);
            
            if (accountId == null || !accounts.containsKey(accountId)) {
                totalSkipped++;
                continue;
            }
            
            Account accountRecord = accounts.get(accountId);
            totalProcessed++;
            
            Long startTime = System.currentTimeMillis();
            try {
                AiFileNamingCalloutService.CalloutResult calloutResult =
                    AiFileNamingCalloutService.generateFileName(rules, accountRecord, cv);
                
                Long elapsed = System.currentTimeMillis() - startTime;
                
                if (calloutResult.success && String.isNotBlank(calloutResult.fileName)) {
                    ContentVersion updateRecord = new ContentVersion(Id = cv.Id);
                    updateRecord.AI_Generated_File_Name__c = calloutResult.fileName.left(255);
                    updateRecord.Title                     = calloutResult.fileName.left(255);
                    updateRecord.AI_Name_Generated__c      = true;
                    updates.add(updateRecord);
                    totalSuccess++;
                    
                    logger.logSuccess(
                        cv.Id, cv.ContentDocumentId,
                        calloutResult.statusCode,
                        calloutResult.fileName,
                        calloutResult.requestPayload,
                        calloutResult.responseBody,
                        elapsed
                    );
                } else {
                    totalFailed++;
                    logger.logApiError(
                        cv.Id, cv.ContentDocumentId,
                        calloutResult.status,
                        calloutResult.statusCode,
                        calloutResult.errorMessage,
                        calloutResult.requestPayload,
                        calloutResult.responseBody,
                        elapsed
                    );
                }
            } catch (Exception ex) {
                Long elapsed = System.currentTimeMillis() - startTime;
                totalFailed++;
                logger.logException(cv.Id, cv.ContentDocumentId, ex, null, elapsed);
            }
        }
        
        // Persist updates with partial success — one record failure won't block others
        if (!updates.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(updates, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (!saveResults[i].isSuccess()) {
                    String errors = '';
                    for (Database.Error err : saveResults[i].getErrors()) {
                        errors += err.getStatusCode() + ': ' + err.getMessage() + '\n';
                    }
                    ContentVersion failedCv = updates[i];
                    logger.logApiError(
                        failedCv.Id, null,
                        'DML_Error', null,
                        'Failed to update ContentVersion: ' + errors,
                        null, null, null
                    );
                    // Adjust counters: was counted as success, now failed
                    totalSuccess--;
                    totalFailed++;
                }
            }
        }
        
        // Flush all log entries for this batch
        logger.flush();
    }
    
    // ──────────────────────────────────────────────
    // Batchable — finish
    // ──────────────────────────────────────────────
    
    public void finish(Database.BatchableContext context) {
        String mode = contentVersionId != null
            ? 'Manual trigger (Id: ' + contentVersionId + ')'
            : 'Scheduler / Bulk flow';
        
        System.debug(LoggingLevel.INFO,
                     'AiFileNamingDailyJob completed [' + mode + '] — '
                     + 'Processed: ' + totalProcessed
                     + ', Success: ' + totalSuccess
                     + ', Failed: '  + totalFailed
                     + ', Skipped: ' + totalSkipped
                    );
        
        if (contentVersionId != null) {
            // ── Case 1: Single record — ek Id k liye ──
            // Specific ContentVersion Id ke liye
            
            
            Database.executeBatch(
                new GeminiFileInsightBackfillBatch(true, false,contentVersionId ),
                1
            );
        } else {
            // ── Case 2: Bulk — sabke liye ──
            
            Database.executeBatch(
                new GeminiFileInsightBackfillBatch(false, false, NULL),
                1
            );
        }
    }
    
    // ──────────────────────────────────────────────
    // Public helpers (preserved for LWC preview)
    // ──────────────────────────────────────────────
    
    /**
* Public entry point used by the LWC Test Run preview.
* Attempts AI naming for a single rule, returns null if AI declines or is unavailable.
*/
    public static String generateFileNameForPreview(
        AI_File_Naming_Rule__c rule,
        Account accountRecord,
        ContentVersion cv
    ) {
        List<AI_File_Naming_Rule__c> singleRule = new List<AI_File_Naming_Rule__c>{ rule };
            AiFileNamingCalloutService.CalloutResult result =
            AiFileNamingCalloutService.generateFileName(singleRule, accountRecord, cv);
        return result.success ? result.fileName : null;
    }
    
    /**
* Deterministic file name builder used as a fallback when AI is unavailable.
*/
    public static String buildDeterministicFileName(
        AI_File_Naming_Rule__c rule,
        Account accountRecord,
        ContentVersion cv
    ) {
        List<String> parts = new List<String>();
        parts.add(cleanFileNamePart(accountRecord.Name));
        parts.add(cleanFileNamePart(rule.Name));
        
        String primaryTag = firstTag(rule.Tags__c);
        if (String.isNotBlank(primaryTag)) {
            parts.add(cleanFileNamePart(primaryTag));
        }
        
        parts.add(cv.CreatedDate == null
                  ? String.valueOf(Date.today())
                  : cv.CreatedDate.format('yyyy-MM-dd'));
        
        String fileType = String.isBlank(cv.FileType) ? null : cv.FileType.toLowerCase();
        String baseName = String.join(removeBlankParts(parts), ' - ');
        return String.isBlank(fileType) ? baseName : baseName + '.' + fileType;
    }
    
    // ──────────────────────────────────────────────
    // Private helpers
    // ──────────────────────────────────────────────
    
    private static Map<Id, Id> resolveLinkedAccounts(Set<Id> contentDocumentIds) {
        Map<Id, Id> docToAccountId = new Map<Id, Id>();
        for (ContentDocumentLink linkRecord : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocumentIds
        ]) {
            if (!docToAccountId.containsKey(linkRecord.ContentDocumentId)
                && linkRecord.LinkedEntityId != null) {
                    docToAccountId.put(linkRecord.ContentDocumentId, linkRecord.LinkedEntityId);
                }
        }
        return docToAccountId;
    }
    
    private static List<AI_File_Naming_Rule__c> getActiveRules() {
        return [
            SELECT Id,
            Name,
            Order__c,
            Is_Active__c,
            Criteria_Mode__c,
            Criteria_Prompt__c,
            Tags__c,
            Action_Prompt__c
            FROM AI_File_Naming_Rule__c
            WHERE Is_Active__c = true
            ORDER BY Order__c ASC NULLS LAST, CreatedDate ASC
        ];
    }
    
    private static String firstTag(String tags) {
        if (String.isBlank(tags)) {
            return null;
        }
        for (String tag : tags.split(',')) {
            if (String.isNotBlank(tag)) {
                return tag.trim();
            }
        }
        return null;
    }
    
    private static List<String> removeBlankParts(List<String> parts) {
        List<String> cleaned = new List<String>();
        for (String part : parts) {
            if (String.isNotBlank(part)) {
                cleaned.add(part);
            }
        }
        return cleaned;
    }
    
    private static String cleanFileNamePart(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.replaceAll('[\\\\/:*?"<>|#%{}~&]', ' ').replaceAll('\\s+', ' ').trim();
    }
}