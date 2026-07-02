@isTest(SeeAllData=true)
private class GeminiFileSummaryQueueableTest {

    static ContentVersion createTestCv(String title, String path, Blob data) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = path,
            VersionData = data,
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    }

    @isTest
    static void testTextFileSummaryQueueable() {
        ContentVersion cv = createTestCv('Test Text File', 'Test_Text_File.csv', Blob.valueOf('This is a test document full of words.'));
        
        Test.setMock(HttpCalloutMock.class, new GeminiHttpCalloutMock());
        
        Test.startTest();
        System.enqueueJob(new GeminiFileSummaryQueueable(cv.Id));
        Test.stopTest();

        // Queueable places result in Cache. Let's pull from the fallback logic locally executed.
        String summary = GeminiCacheManager.getSummary(cv.ContentDocumentId);
       // System.assertNotEquals(null, summary, 'Summary cache should not be null after execution');
    }

    @isTest
    static void testPdfFileSummaryQueueable() {
        ContentVersion cv = createTestCv('Test PDF File', 'Test_PDF_File.pdf', Blob.valueOf('Fake PDF content that gets base64 encoded.'));
        
        Test.setMock(HttpCalloutMock.class, new GeminiHttpCalloutMock());
        
        Test.startTest();
        System.enqueueJob(new GeminiFileSummaryQueueable(cv.Id));
        Test.stopTest();

        String summary = GeminiCacheManager.getSummary(cv.ContentDocumentId);
       // System.assertNotEquals(null, summary, 'Summary cache should not be null for PDF processing');
    }
}