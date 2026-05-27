@isTest
private class GeminiFileInsightLoggerTest {

    private class LoggerTestException extends Exception {}

    private static ContentVersion createTestContentVersion() {
        ContentVersion cv = new ContentVersion(
            Title        = 'Logger Test File',
            PathOnClient = 'logger-test.txt',
            VersionData  = Blob.valueOf('test data')
        );
        insert cv;
        return [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
    }

    @isTest
    static void logSuccessBuffersThenFlushes() {
        ContentVersion cv = createTestContentVersion();
        String jobId = '707000000000001';

        Test.startTest();
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger(jobId);
        logger.logSuccess(cv.Id, cv.ContentDocumentId, 'My File - AI Generated Summary', 1234L);

        // Buffered, not yet inserted
        System.assertEquals(0, [SELECT COUNT() FROM Gemini_Insight_Log__c],
            'No rows should be persisted before flush()');

        logger.flush();
        Test.stopTest();

        Gemini_Insight_Log__c row = [
            SELECT Status__c, Content_Version_Id__c, Content_Document_Id__c,
                   Generated_File_Name__c, Processing_Time_Ms__c, Batch_Job_Id__c, Error_Message__c
            FROM Gemini_Insight_Log__c
            LIMIT 1
        ];
        System.assertEquals(GeminiFileInsightLogger.STATUS_SUCCESS, row.Status__c);
        System.assertEquals(String.valueOf(cv.Id), row.Content_Version_Id__c);
        System.assertEquals(String.valueOf(cv.ContentDocumentId), row.Content_Document_Id__c);
        System.assertEquals('My File - AI Generated Summary', row.Generated_File_Name__c);
        System.assertEquals(1234, row.Processing_Time_Ms__c);
        System.assertEquals(jobId, row.Batch_Job_Id__c);
        System.assertEquals(null, row.Error_Message__c);
    }

    @isTest
    static void logSkippedNoAccountWritesExpectedRow() {
        ContentVersion cv = createTestContentVersion();

        Test.startTest();
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger(null);
        logger.logSkippedNoAccount(cv.Id, cv.ContentDocumentId);
        logger.flush();
        Test.stopTest();

        Gemini_Insight_Log__c row = [
            SELECT Status__c, Error_Message__c, Generated_File_Name__c, Processing_Time_Ms__c
            FROM Gemini_Insight_Log__c
            LIMIT 1
        ];
        System.assertEquals(GeminiFileInsightLogger.STATUS_SKIPPED_NO_ACCOUNT, row.Status__c);
        System.assert(row.Error_Message__c != null
            && row.Error_Message__c.contains('not linked to an Account'),
            'Skip log must explain why');
        System.assertEquals(null, row.Generated_File_Name__c);
        System.assertEquals(null, row.Processing_Time_Ms__c);
    }

    @isTest
    static void logSkippedHasExistingAiWritesExpectedRow() {
        ContentVersion cv = createTestContentVersion();

        Test.startTest();
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger(null);
        logger.logSkippedHasExistingAi(cv.Id, cv.ContentDocumentId);
        logger.flush();
        Test.stopTest();

        Gemini_Insight_Log__c row = [
            SELECT Status__c, Error_Message__c
            FROM Gemini_Insight_Log__c
            LIMIT 1
        ];
        System.assertEquals(GeminiFileInsightLogger.STATUS_SKIPPED_HAS_AI, row.Status__c);
        System.assert(row.Error_Message__c.contains('Existing AI summary file found'),
            'Skip log must explain the existing-AI reason');
    }

    @isTest
    static void logFailureCapturesExceptionDetail() {
        ContentVersion cv = createTestContentVersion();

        Test.startTest();
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger('jobX');
        try {
            throw new LoggerTestException('boom from test');
        } catch (Exception ex) {
            logger.logFailure(cv.Id, cv.ContentDocumentId, ex, 5000L);
        }
        logger.flush();
        Test.stopTest();

        Gemini_Insight_Log__c row = [
            SELECT Status__c, Error_Message__c, Processing_Time_Ms__c, Batch_Job_Id__c
            FROM Gemini_Insight_Log__c
            LIMIT 1
        ];
        System.assertEquals(GeminiFileInsightLogger.STATUS_FAILED, row.Status__c);
        System.assert(row.Error_Message__c.contains('boom from test'),
            'Exception message must be captured');
        System.assert(row.Error_Message__c.contains('LoggerTestException'),
            'Exception type must be captured');
        System.assertEquals(5000, row.Processing_Time_Ms__c);
        System.assertEquals('jobX', row.Batch_Job_Id__c);
    }

    @isTest
    static void logFailureWithNullExceptionUsesFallback() {
        ContentVersion cv = createTestContentVersion();

        Test.startTest();
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger(null);
        logger.logFailure(cv.Id, cv.ContentDocumentId, null, null);
        logger.flush();
        Test.stopTest();

        Gemini_Insight_Log__c row = [
            SELECT Status__c, Error_Message__c, Processing_Time_Ms__c
            FROM Gemini_Insight_Log__c
            LIMIT 1
        ];
        System.assertEquals(GeminiFileInsightLogger.STATUS_FAILED, row.Status__c);
        System.assertEquals('Unknown error', row.Error_Message__c);
        System.assertEquals(null, row.Processing_Time_Ms__c);
    }

    @isTest
    static void flushIsIdempotent() {
        ContentVersion cv = createTestContentVersion();

        Test.startTest();
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger(null);
        logger.logSkippedNoAccount(cv.Id, cv.ContentDocumentId);
        logger.flush();
        // Second flush must be a no-op since the buffer was cleared
        logger.flush();
        logger.flush();
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Gemini_Insight_Log__c],
            'Repeated flush() calls must not duplicate rows');
    }

    @isTest
    static void flushOnEmptyBufferIsNoop() {
        Test.startTest();
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger('emptyJob');
        logger.flush();
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Gemini_Insight_Log__c]);
    }

    @isTest
    static void multipleLogsFlushTogether() {
        ContentVersion cv = createTestContentVersion();

        Test.startTest();
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger('multiJob');
        logger.logSuccess(cv.Id, cv.ContentDocumentId, 'a.pdf', 100L);
        logger.logSkippedNoAccount(cv.Id, cv.ContentDocumentId);
        logger.logSkippedHasExistingAi(cv.Id, cv.ContentDocumentId);
        logger.logFailure(cv.Id, cv.ContentDocumentId, new LoggerTestException('x'), 200L);
        logger.flush();
        Test.stopTest();

        Map<String, Integer> counts = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Status__c, COUNT(Id) cnt
            FROM Gemini_Insight_Log__c
            WHERE Batch_Job_Id__c = 'multiJob'
            GROUP BY Status__c
        ]) {
            counts.put((String) ar.get('Status__c'), (Integer) ar.get('cnt'));
        }
        System.assertEquals(1, counts.get(GeminiFileInsightLogger.STATUS_SUCCESS));
        System.assertEquals(1, counts.get(GeminiFileInsightLogger.STATUS_SKIPPED_NO_ACCOUNT));
        System.assertEquals(1, counts.get(GeminiFileInsightLogger.STATUS_SKIPPED_HAS_AI));
        System.assertEquals(1, counts.get(GeminiFileInsightLogger.STATUS_FAILED));
    }

    @isTest
    static void nullIdsAreHandledGracefully() {
        Test.startTest();
        GeminiFileInsightLogger logger = new GeminiFileInsightLogger(null);
        logger.logSkippedNoAccount(null, null);
        logger.flush();
        Test.stopTest();

        Gemini_Insight_Log__c row = [
            SELECT Content_Version_Id__c, Content_Document_Id__c, Status__c
            FROM Gemini_Insight_Log__c
            LIMIT 1
        ];
        System.assertEquals(null, row.Content_Version_Id__c);
        System.assertEquals(null, row.Content_Document_Id__c);
        System.assertEquals(GeminiFileInsightLogger.STATUS_SKIPPED_NO_ACCOUNT, row.Status__c);
    }
}