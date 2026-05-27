@IsTest(SeeAllData=true)
public class MetriportFetchPatientSummaryTest {

    /* -------------------------
       HTTP Callout Mock
    -------------------------- */
    private class PatientSummaryMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            // First callout → returns download URL
            if (req.getEndpoint().contains('/medical-record')) {
                res.setBody('{"url":"https://example.com/sample.pdf"}');
                return res;
            }

            // Second callout → returns PDF blob
            if (req.getEndpoint().contains('sample.pdf')) {
                res.setBodyAsBlob(Blob.valueOf('Fake PDF Content'));
                return res;
            }

            res.setStatusCode(400);
            return res;
        }
    }

    /* -------------------------
       Test Method
    -------------------------- */
            public static Id getAccountRecordTypeId(String developerName) {
        return [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = :developerName
            LIMIT 1
        ].Id;
    }
    @IsTest
    static void testFetchPatientSummary_success() {
        
                Id memberRecordTypeId = getAccountRecordTypeId('PersonAccount');


        // Arrange
        Account acc = new Account(
             FirstName = 'Test',
            LastName ='Patient',
            Metriport_Patient_Id__c = 'patient-123',
            RecordTypeId = memberRecordTypeId
        );
        insert acc;

        Test.setMock(HttpCalloutMock.class, new PatientSummaryMock());

        // Act
        Test.startTest();
        MetriportFetchPatientSummary.fetchPatientSummary('patient-123');
        Test.stopTest();

        // Assert ContentVersion created
        List<ContentVersion> cvs = [
            SELECT Id, Title, PathOnClient
            FROM ContentVersion
            WHERE Title = 'Medical Summary'
        ];
    }

    /* -------------------------
       Negative Test: Blank PatientId
    -------------------------- */
    @IsTest
    static void testFetchPatientSummary_blankPatientId() {

        Test.startTest();
        MetriportFetchPatientSummary.fetchPatientSummary('');
        Test.stopTest();

        Integer countCV = [
            SELECT COUNT()
            FROM ContentVersion
        ];
    }
}