/**
 * Logging service for the Gemini file insight backfill batch.
 * Mirrors the AiFileNamingLogger pattern: buffers entries during execute()
 * and flushes them in bulk via Database.insert(allOrNone=false), so logging
 * never causes the batch transaction to fail.
 *
 * Persists to Gemini_Insight_Log__c — a dedicated audit object for this batch.
 */
public with sharing class GeminiFileInsightLogger {

    public static final String STATUS_SUCCESS              = 'Insight_Success';
    public static final String STATUS_SKIPPED_NO_ACCOUNT   = 'Insight_Skipped_NoAccount';
    public static final String STATUS_SKIPPED_HAS_AI       = 'Insight_Skipped_HasAi';
    public static final String STATUS_FAILED               = 'Insight_Failed';

    private List<Gemini_Insight_Log__c> buffer = new List<Gemini_Insight_Log__c>();
    private String batchJobId;

    public GeminiFileInsightLogger(String batchJobId) {
        this.batchJobId = batchJobId;
    }

    /**
     * Log a successful insight regeneration. analysisTitle is recorded in
     * Generated_File_Name__c so the AI summary that was produced can be traced.
     */
    public void logSuccess(
        Id contentVersionId,
        Id contentDocumentId,
        String analysisTitle,
        Long processingTimeMs
    ) {
        buffer.add(buildLog(
            contentVersionId,
            contentDocumentId,
            STATUS_SUCCESS,
            null,
            null,
            analysisTitle,
            processingTimeMs
        ));
    }

    /**
     * Log a skip — source has no Account ContentDocumentLink, so insight
     * generation is not applicable.
     */
    public void logSkippedNoAccount(Id contentVersionId, Id contentDocumentId) {
        buffer.add(buildLog(
            contentVersionId,
            contentDocumentId,
            STATUS_SKIPPED_NO_ACCOUNT,
            null,
            'Source ContentDocument is not linked to an Account; insight generation skipped.',
            null,
            null
        ));
    }

    /**
     * Log a skip — source already has an AI summary file linked. Regeneration
     * is suppressed in batch context to avoid the controller's delete DML
     * firing ContentDocumentDeleteTrigger.
     */
    public void logSkippedHasExistingAi(Id contentVersionId, Id contentDocumentId) {
        buffer.add(buildLog(
            contentVersionId,
            contentDocumentId,
            STATUS_SKIPPED_HAS_AI,
            null,
            'Existing AI summary file found for this source; regeneration skipped.',
            null,
            null
        ));
    }

    /**
     * Log a failed regeneration attempt with full exception detail.
     */
    public void logFailure(
        Id contentVersionId,
        Id contentDocumentId,
        Exception ex,
        Long processingTimeMs
    ) {
        String errorDetail = ex == null
            ? 'Unknown error'
            : ex.getTypeName() + ': ' + ex.getMessage() + '\n' + ex.getStackTraceString();
        buffer.add(buildLog(
            contentVersionId,
            contentDocumentId,
            STATUS_FAILED,
            null,
            errorDetail,
            null,
            processingTimeMs
        ));
    }

    /**
     * Persist all buffered entries. Safe to call multiple times; uses
     * allOrNone=false so a single bad row never breaks the batch.
     */
    public void flush() {
        if (buffer.isEmpty()) {
            return;
        }
        Database.insert(buffer, false);
        buffer.clear();
    }

    @TestVisible
    private Integer pendingCount() {
        return buffer.size();
    }

    private Gemini_Insight_Log__c buildLog(
        Id contentVersionId,
        Id contentDocumentId,
        String status,
        Integer statusCode,
        String errorMessage,
        String generatedFileName,
        Long processingTimeMs
    ) {
        Gemini_Insight_Log__c log = new Gemini_Insight_Log__c();
        log.Content_Version_Id__c  = contentVersionId  != null ? String.valueOf(contentVersionId)  : null;
        log.Content_Document_Id__c = contentDocumentId != null ? String.valueOf(contentDocumentId) : null;
        log.Status__c              = status;
        log.Status_Code__c         = statusCode;
        log.Error_Message__c       = truncate(errorMessage, 131072);
        log.Generated_File_Name__c = generatedFileName;
        log.Processing_Time_Ms__c  = processingTimeMs;
        log.Batch_Job_Id__c        = batchJobId;
        return log;
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}