@IsTest
private class MetriportHandlerTest {

    @IsTest
    static void testHandleWebhookSuccess() {
        // Prepare a fake JSON payload
        String fakeJson = '{"name":"Test","value":123}';
        
        // Mock REST request
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/api/metriport/webhook/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(fakeJson);
        RestContext.request = req;

        RestResponse res = new RestResponse();
        RestContext.response = res;

        // Execute handler in test context
        Test.startTest();
        MetriportHandler.handleWebhook();
        Test.stopTest();

        // Assert success response
        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void testHandleWebhookException() {
        // Simulate a request that will fail (null body)
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/api/metriport/webhook/';
        req.httpMethod = 'POST';
        req.requestBody = null; // triggers exception when toString() is called
        RestContext.request = req;

        RestResponse res = new RestResponse();
        RestContext.response = res;

        Test.startTest();
        MetriportHandler.handleWebhook();
        Test.stopTest();

        // Assert error response
        System.assertEquals(500, RestContext.response.statusCode);
    }
}