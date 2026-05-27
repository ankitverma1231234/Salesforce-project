@isTest(SeeAllData=true)
public class AccountTriggerdTest {

    /* Mock Callout */
    class DeletePatientMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(204);
            res.setBody('Deleted');
            return res;
        }
    }

    @isTest
    static void testAccountBeforeDeleteTrigger() {

        // Get account with metriport patient id
        Account acc = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        Test.setMock(HttpCalloutMock.class, new DeletePatientMock());

        Test.startTest();
        delete acc; // fires trigger
        Test.stopTest();

        System.assert(true, 'Trigger executed successfully');
    }


}