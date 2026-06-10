@IsTest(SeeAllData=true)
private class MetriportNetworkQueryServiceTest {

    private static String getPatientId() {
        Account acc = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        return acc.Metriport_Patient_Id__c;
    }

    private class SuccessMock implements HttpCalloutMock {
        Integer statusCode;
        String body;

        SuccessMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {

            System.assertEquals('POST', req.getMethod());
            System.assert(
                req.getEndpoint().contains('/medical/v1/network/query')
            );

            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    private class ExceptionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Connection timeout');
        }
    }

    @IsTest
    static void testBlankPatientId() {
        try {
            MetriportNetworkQueryService.initiateNetworkQuery(null);
            System.assert(false);
        } catch (AuraHandledException e) {

        }
    }

    @IsTest
    static void testSuccess200() {

        Test.setMock(
            HttpCalloutMock.class,
            new SuccessMock(200, '{"requestId":"123"}')
        );

        Test.startTest();

        String result =
            MetriportNetworkQueryService.initiateNetworkQuery(
                getPatientId()
            );

        Test.stopTest();

        System.assertEquals('{"requestId":"123"}', result);
    }

    @IsTest
    static void testSuccessEmptyBody() {

        Test.setMock(
            HttpCalloutMock.class,
            new SuccessMock(202, '')
        );

        Test.startTest();

        String result =
            MetriportNetworkQueryService.initiateNetworkQuery(
                getPatientId()
            );

        Test.stopTest();

        System.assertEquals(
            '{"status":"accepted"}',
            result
        );
    }

    @IsTest
    static void testHttpFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new ErrorMock()
        );

        try {
            Test.startTest();

            MetriportNetworkQueryService.initiateNetworkQuery(
                getPatientId()
            );

            Test.stopTest();
            System.assert(false);

        } catch (AuraHandledException e) {


        }

        List<Error_Log__c> logs = [
            SELECT Id,
                   Error_Message__c,
                   Record_External_Id__c
            FROM Error_Log__c
            WHERE Record_External_Id__c = 'patient-123'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.assertEquals(1, logs.size());
        System.assertEquals(
            'Internal Server Error',
            logs[0].Error_Message__c
        );
    }

    @IsTest
    static void testCalloutException() {

        Test.setMock(
            HttpCalloutMock.class,
            new ExceptionMock()
        );

        try {
            Test.startTest();

            MetriportNetworkQueryService.initiateNetworkQuery(
                getPatientId()
            );

            Test.stopTest();
            System.assert(false);

        } catch (AuraHandledException e) {

        }

        List<Error_Log__c> logs = [
            SELECT Id,
                   Error_Message__c,
                   Record_External_Id__c
            FROM Error_Log__c
            WHERE Record_External_Id__c = 'patient-123'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.assertEquals(1, logs.size());
        System.assert(
            logs[0].Error_Message__c.contains('Connection timeout')
        );
    }
}