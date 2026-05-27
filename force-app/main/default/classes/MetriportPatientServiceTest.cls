@IsTest(seeAllData=true)
public class MetriportPatientServiceTest {

    private class MetriportPatientMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(201);
            res.setBody('{"id":"patient-123"}');
            return res;
        }
    }

    @IsTest
    static void testCreateMetriportPatients_multipleScenarios() {

        Account acc = [
            SELECT Id, FirstName, LastName, Maiden_Name__pc, Date_of_Birth__pc,
                   PersonEmail, PersonMobilePhone, Biological_Sex_at_Birth__c,
                   PersonMailingStreet, PersonOtherStreet, PersonMailingCity,
                   PersonMailingStateCode, PersonMailingPostalCode
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        System.assertNotEquals(null, acc);

        Test.setMock(HttpCalloutMock.class, new MetriportPatientMock());

        // Modify data BEFORE startTest (simulate different branches)
        acc.Biological_Sex_at_Birth__c = 'Male';
        acc.Date_of_Birth__pc = Date.newInstance(1990, 5, 10);
        acc.Maiden_Name__pc = 'Test';
        update acc;

        Map<Id, String> accountMap = new Map<Id, String>{
            acc.Id => 'EXT-1'
        };

        Test.startTest();
            MetriportPatientService.createMetriportPatients(accountMap);
        Test.stopTest();

        Account updatedAcc = [
            SELECT Metriport_Patient_Id__c
            FROM Account
            WHERE Id = :acc.Id
        ];

        System.assertEquals('patient-123', updatedAcc.Metriport_Patient_Id__c);
    }

    @IsTest
    static void testEmptyMap() {
        Test.startTest();
            MetriportPatientService.createMetriportPatients(new Map<Id, String>());
        Test.stopTest();
    }
}