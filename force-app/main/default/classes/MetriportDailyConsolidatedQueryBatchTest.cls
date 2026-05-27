@isTest(seealldata=true)
private class MetriportDailyConsolidatedQueryBatchTest {

    /***************
     * Mock Callout
     ***************/
    private class MetriportMock implements HttpCalloutMock {
        private Integer statusCode;

        public MetriportMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);
            res.setBody('{"status":"processing"}');
            return res;
        }
    }

    /***************
     * Tests
     ***************/
    @isTest
    static void testBatchSuccessfulCallout() {
        List<Account> accList = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        Assert.isFalse(accList.isEmpty(), 'Test account with Metriport ID patient-123 should exist in org');

        Test.setMock(HttpCalloutMock.class, new MetriportMock(200));

        Test.startTest();
        MetriportDailyConsolidatedQueryBatch batch = new MetriportDailyConsolidatedQueryBatch();
        MetriportClinicalSummaryBatch batch2 = new MetriportClinicalSummaryBatch();
        batch.execute(null, accList);
        batch2.execute(null,accList);
        Test.stopTest();
    }

    @isTest
    static void testBatchApiErrorResponse() {
        List<Account> accList = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        Assert.isFalse(accList.isEmpty(), 'Account should exist in org');

        // Simulate API returning 500 - batch should still complete without throwing
        Test.setMock(HttpCalloutMock.class, new MetriportMock(500));

        Test.startTest();
        MetriportDailyConsolidatedQueryBatch batch = new MetriportDailyConsolidatedQueryBatch();
        MetriportClinicalSummaryBatch batch2 = new MetriportClinicalSummaryBatch();
        batch.execute(null, accList);
        batch2.execute(null,accList);
        Test.stopTest();
    }


}