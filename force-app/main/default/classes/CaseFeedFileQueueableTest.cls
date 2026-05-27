@IsTest
public class CaseFeedFileQueueableTest {
    // Mock Class
    class MockHttpResponseGenerator implements HttpCalloutMock{
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/octet-stream');
            res.setBodyAsBlob(Blob.valueOf('Test File Content'));
            return res;
        }
    }
    
    @IsTest
    Static void testQueueableSuccess(){
        Case testcase = new case(
        Subject = 'Test case',
        Status = 'New',
        Origin = 'Phone');
        Insert testcase;
        
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        Test.StartTest();
        System.enqueueJob( new CaseFeedFileQueueable(testCase.Id,
                'https://example.com/testfile',
                'TestFile.txt'));
       Test.stopTest();
        // Verify Attachment Created
        List<Attachment> attachments = [
            SELECT Id, Name, ParentId
            FROM Attachment
            WHERE ParentId = :testCase.Id
        ];
        System.assertEquals(1, attachments.size());
        System.assertEquals('TestFile.txt', attachments[0].Name);
    }
}