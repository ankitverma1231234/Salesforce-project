/**
 * Centralized logging service for AI File Naming batch operations.
 * Buffers log entries during batch execution and flushes them in bulk
 * to avoid hitting DML limits per transaction.
 */
public with sharing class AiFileNamingLogger {

    private List<AI_File_Naming_Log__c> buffer = new List<AI_File_Naming_Log__c>();
    private String batchJobId;

    public AiFileNamingLogger(String batchJobId) {
        this.batchJobId = batchJobId;
    }

    /**
     * Log a successful AI naming result.
     */
    public void logSuccess(
        Id contentVersionId,
        Id contentDocumentId,
        Integer statusCode,
        String generatedFileName,
        String requestPayload,
        String responsePayload,
        Long processingTimeMs
    ) {
        buffer.add(buildLog(
            contentVersionId,
            contentDocumentId,
            'Success',
            statusCode,
            null,
            generatedFileName,
            requestPayload,
            responsePayload,
            processingTimeMs
        ));
    }

    /**
     * Log an API error (non-200 status, invalid response, no match).
     */
    public void logApiError(
        Id contentVersionId,
        Id contentDocumentId,
        String status,
        Integer statusCode,
        String errorMessage,
        String requestPayload,
        String responsePayload,
        Long processingTimeMs
    ) {
        buffer.add(buildLog(
            contentVersionId,
            contentDocumentId,
            status,
            statusCode,
            errorMessage,
            null,
            requestPayload,
            responsePayload,
            processingTimeMs
        ));
    }

    /**
     * Log an unhandled exception during processing.
     */
    public void logException(
        Id contentVersionId,
        Id contentDocumentId,
        Exception ex,
        String requestPayload,
        Long processingTimeMs
    ) {
        String errorDetail = ex.getTypeName() + ': ' + ex.getMessage() + '\n' + ex.getStackTraceString();
        buffer.add(buildLog(
            contentVersionId,
            contentDocumentId,
            'Exception',
            null,
            errorDetail,
            null,
            requestPayload,
            null,
            processingTimeMs
        ));
    }

    /**
     * Persist all buffered log entries. Safe to call multiple times;
     * uses Database.insert with allOrNone=false so logging never
     * causes the batch transaction to fail.
     */
    public void flush() {
        if (buffer.isEmpty()) {
            return;
        }
        Database.insert(buffer, false);
        buffer.clear();
    }

    /**
     * Returns the number of pending (unflushed) log entries.
     */
    public Integer pendingCount() {
        return buffer.size();
    }

    private AI_File_Naming_Log__c buildLog(
        Id contentVersionId,
        Id contentDocumentId,
        String status,
        Integer statusCode,
        String errorMessage,
        String generatedFileName,
        String requestPayload,
        String responsePayload,
        Long processingTimeMs
    ) {
        AI_File_Naming_Log__c log = new AI_File_Naming_Log__c();
        log.Content_Version_Id__c  = contentVersionId != null ? String.valueOf(contentVersionId) : null;
        log.Content_Document_Id__c = contentDocumentId != null ? String.valueOf(contentDocumentId) : null;
        log.Status__c              = status;
        log.Status_Code__c         = statusCode;
        log.Error_Message__c       = truncate(errorMessage, 131072);
        log.Generated_File_Name__c = generatedFileName;
        log.Request_Payload__c     = truncate(requestPayload, 131072);
        log.Response_Payload__c    = truncate(responsePayload, 131072);
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