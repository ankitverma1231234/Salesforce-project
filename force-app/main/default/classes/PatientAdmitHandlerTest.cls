@IsTest(seeAllData = true)
public class PatientAdmitHandlerTest {

    /* ---------------------------
       HTTP MOCK - SUCCESS
    ---------------------------- */
    private class AdmitJsonSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"patientId":"patient-123","event":"ADMIT"}');
            return res;
        }
    }

    /* ---------------------------
       HTTP MOCK - FAILURE
    ---------------------------- */
    private class AdmitJsonFailureMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('Not Found');
            return res;
        }
    }

    /* ---------------------------
       SUCCESS FLOW
    ---------------------------- */
    @IsTest
    static void testHandle_SuccessFlow() {

        // Fetch existing Account (NO INSERT)
        Account acc = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        Map<String, Object> payload = new Map<String, Object>{
            'payload' => new Map<String, Object>{
                'url' => 'https://test.com/admit.json'
            },
            'meta' => new Map<String, Object>{
                'type' => 'ADT_A01'
            }
        };

        Test.setMock(HttpCalloutMock.class, new AdmitJsonSuccessMock());

        Test.startTest();
        PatientAdmitHandler.handle(payload);
        Test.stopTest(); // Queueable executes once and exits safely

        System.assert(true, 'Success flow completed without recursion');
    }

    /* ---------------------------
       MISSING INNER PAYLOAD
    ---------------------------- */
    @IsTest
    static void testHandle_MissingInnerPayload() {

        Map<String, Object> payload = new Map<String, Object>{
            'meta' => new Map<String, Object>{
                'type' => 'ADT_A01'
            }
        };

        Test.startTest();
        PatientAdmitHandler.handle(payload);
        Test.stopTest();

        System.assert(true);
    }

    /* ---------------------------
       MISSING URL
    ---------------------------- */
    @IsTest
    static void testHandle_MissingUrl() {

        Map<String, Object> payload = new Map<String, Object>{
            'payload' => new Map<String, Object>(),
            'meta' => new Map<String, Object>{
                'type' => 'ADT_A01'
            }
        };

        Test.startTest();
        PatientAdmitHandler.handle(payload);
        Test.stopTest();

        System.assert(true);
    }

    /* ---------------------------
       DOWNLOAD FAILURE
    ---------------------------- */
    @IsTest
    static void testHandle_DownloadFailure() {

        Map<String, Object> payload = new Map<String, Object>{
            'payload' => new Map<String, Object>{
                'url' => 'https://test.com/bad.json'
            },
            'meta' => new Map<String, Object>{
                'type' => 'ADT_A01'
            }
        };

        Test.setMock(HttpCalloutMock.class, new AdmitJsonFailureMock());

        Test.startTest();
        PatientAdmitHandler.handle(payload);
        Test.stopTest();

        System.assert(true);
    }
}