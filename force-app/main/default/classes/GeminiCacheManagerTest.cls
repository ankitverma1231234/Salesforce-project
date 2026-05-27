@isTest
private class GeminiCacheManagerTest {

    @isTest
    static void testSummaryCache_NoExceptionWhenPartitionUnavailable() {
        Id docId = '069000000000001AAA';
        String summaryBody = 'This is a test summary.';

        Test.startTest();
        GeminiCacheManager.putSummary(docId, summaryBody);
        String cachedValue = GeminiCacheManager.getSummary(docId);
        GeminiCacheManager.removeSummary(docId);
        String deletedValue = GeminiCacheManager.getSummary(docId);
        Test.stopTest();

        System.assert(cachedValue == null || cachedValue == summaryBody,
            'Summary cache should either store the value or no-op safely when the partition is unavailable');
        System.assertEquals(null, deletedValue, 'Summary should be null after removal or cache no-op');
    }

    @isTest
    static void testAnalysisCache_NoExceptionWhenPartitionUnavailable() {
        Id docId = '069000000000002AAA';
        String jsonAnalysis = '{"title":"Test"}';

        Test.startTest();
        GeminiCacheManager.putAnalysis(docId, jsonAnalysis);
        String cachedValue = GeminiCacheManager.getAnalysis(docId);
        GeminiCacheManager.removeAnalysis(docId);
        String deletedValue = GeminiCacheManager.getAnalysis(docId);
        Test.stopTest();

        System.assert(cachedValue == null || cachedValue == jsonAnalysis,
            'Analysis cache should either store the value or no-op safely when the partition is unavailable');
        System.assertEquals(null, deletedValue, 'Analysis should be null after removal or cache no-op');
    }

    @isTest
    static void testCacheMethods_WithNullId() {
        Test.startTest();
        Boolean summaryThrew = false;
        Boolean analysisThrew = false;

        try {
            GeminiCacheManager.putSummary(null, 'null-summary');
        } catch (Exception e) {
            summaryThrew = true;
            System.assert(e instanceof NullPointerException,
                'Null summary key access should currently fail with a NullPointerException');
        }

        try {
            GeminiCacheManager.putAnalysis(null, '{"value":"null-analysis"}');
        } catch (Exception e) {
            analysisThrew = true;
            System.assert(e instanceof NullPointerException,
                'Null analysis key access should currently fail with a NullPointerException');
        }
        Test.stopTest();

        System.assertEquals(true, summaryThrew, 'Null summary input should throw');
        System.assertEquals(true, analysisThrew, 'Null analysis input should throw');
    }
}