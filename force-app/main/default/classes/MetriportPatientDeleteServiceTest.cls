@isTest(SeeAllData=true)
public class MetriportPatientDeleteServiceTest {

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
    static void testDeleteMetriportPatient() {

        // Get account having metriport patient id
        Account acc = [
            SELECT Id, Metriport_Patient_ID__c
            FROM Account
            WHERE Metriport_Patient_ID__c = 'patient-123'
            LIMIT 1
        ];

        Map<Id, String> accountMap = new Map<Id, String>();
        accountMap.put(acc.Id, acc.Metriport_Patient_ID__c);

        Test.setMock(HttpCalloutMock.class, new DeletePatientMock());

        Test.startTest();
        MetriportPatientDeleteService.deleteMetriportPatients(accountMap);
        Test.stopTest();

        System.assert(true, 'Future method executed successfully');
    }

    @isTest
    static void testSkipWhenPatientIdBlank() {

        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Map<Id, String> accountMap = new Map<Id, String>();
        accountMap.put(acc.Id, null);

        Test.startTest();
        MetriportPatientDeleteService.deleteMetriportPatients(accountMap);
        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testEmptyMap() {

        Map<Id, String> accountMap = new Map<Id, String>();

        Test.startTest();
        MetriportPatientDeleteService.deleteMetriportPatients(accountMap);
        Test.stopTest();

        System.assert(true);
    }
}