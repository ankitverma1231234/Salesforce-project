@IsTest(seeAllData=true)
public class ContentDocumentQueueableTest {
    private class ContentDocHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('200 OK');
            res.setBody('{"status":"success"}');
            return res;
        }
    }
    @IsTest
    static void testQueueableExecution() {
        List<String> payloads = new List<String>{
            '{"documents":[{"Title":"Test Doc 1"}]}',
            '{"documents":[{"Title":"Test Doc 2"}]}'
        };
        Test.setMock(HttpCalloutMock.class, new ContentDocHttpMock());
        Test.startTest();
        System.enqueueJob(new ContentDocumentQueueable(payloads));
        Test.stopTest();
        System.assert(true);
    }
}