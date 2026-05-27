@IsTest
private class MetriportFilteredDataTest {

    /**
     * Utility method to prepare RestContext
     */
    private static void setupRestContext(String body) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/Metriport/Filtered/Data/';
        req.httpMethod = 'POST';

        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }

        RestContext.request = req;
        RestContext.response = res;
    }

    /**
     * Test successful execution with valid JSON body
     */
    @IsTest
    static void testHandleWebhook_Success() {

        // Arrange
        String jsonBody = '{"name":"Test Patient","id":"123"}';
        setupRestContext(jsonBody);

        // Act
        Test.startTest();
        MetriportFilteredData.handleWebhook();
        Test.stopTest();

        // Assert
        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Expected HTTP 200 for valid request body'
        );
    }

    /**
     * Test blank request body
     */
    @IsTest
    static void testHandleWebhook_BlankBody() {

        // Arrange
        setupRestContext('');

        // Act
        Test.startTest();
        MetriportFilteredData.handleWebhook();
        Test.stopTest();

        // Assert
        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Expected HTTP 400 for blank request body'
        );
    }

    /**
     * Test null request body
     */
    @IsTest
    static void testHandleWebhook_NullBody() {

        // Arrange
        setupRestContext(null);

        // Act
        Test.startTest();
        MetriportFilteredData.handleWebhook();
        Test.stopTest();

        // Assert
        System.assertEquals(
            500,
            RestContext.response.statusCode,
            'Expected HTTP 500 when requestBody is null'
        );
    }

    /**
     * Test exception handling explicitly
     * by forcing malformed RestContext
     */
    @IsTest
    static void testHandleWebhook_ExceptionPath() {

        // Arrange
        RestContext.request = null;
        RestContext.response = new RestResponse();

        // Act
        Test.startTest();
        MetriportFilteredData.handleWebhook();
        Test.stopTest();

        // Assert
        System.assertEquals(
            500,
            RestContext.response.statusCode,
            'Expected HTTP 500 when exception occurs'
        );
    }
}