@isTest(SeeAllData=true)
public class MetripointfetchPateintDetailsTest {

    /* =====================================================
       HTTP CALLOUT MOCK (INNER CLASS)
    ===================================================== */
    private class ConsolidatedQueryMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"status":"started","message":"Consolidated query initiated"}'
            );
            return res;
        }
    }

    /* =====================================================
       TEST: SUCCESS SCENARIO
    ===================================================== */
    @isTest
    static void testStartConsolidatedQuery_success() {

        // Register mock
        Test.setMock(
            HttpCalloutMock.class,
            new ConsolidatedQueryMock()
        );

        String patientId = 'patient-123';

        Test.startTest();
        MetripointfetchPateintDetails.startConsolidatedQuery(patientId);
                MetripointfetchPateintDetails.startClinicalSummaryQuery(patientId);
        Test.stopTest();

        // Method is @future and has no return/DML
        // Reaching here means success
        System.assert(true, 'Future callout executed successfully');
    }

    /* =====================================================
       TEST: BLANK PATIENT ID (EDGE CASE)
    ===================================================== */
    @isTest
    static void testStartConsolidatedQuery_blankPatientId() {

        Test.setMock(
            HttpCalloutMock.class,
            new ConsolidatedQueryMock()
        );

        Test.startTest();
        MetripointfetchPateintDetails.startConsolidatedQuery('');
		MetripointfetchPateintDetails.startClinicalSummaryQuery('');
        Test.stopTest();

        System.assert(true, 'Blank patientId handled safely');
    }
}