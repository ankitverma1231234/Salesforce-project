@IsTest
public class MetriportPatientWebhookTest {

    // Helper to build RestContext
    private static void setupRestContext(String body) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestUri = '/services/apexrest/api/metriport/webhook/patient/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);

        RestContext.request = req;
        RestContext.response = res;
    }

    // 🔹 Test: patient.admit (happy path)
    @IsTest
    static void testPatientAdmitEvent() {
        String body = JSON.serialize(new Map<String, Object>{
            'metaType' => 'patient.admit',
            'id' => '123'
        });

        setupRestContext(body);

        Test.startTest();
        MetriportPatientWebhook.handleWebhook();
        Test.stopTest(); // ensures Queueable runs

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Expected 200 for patient.admit'
        );
    }

    // 🔹 Test: non-patient event (ignored)
    @IsTest
    static void testNonPatientEvent() {
        String body = JSON.serialize(new Map<String, Object>{
            'metaType' => 'document.created'
        });

        setupRestContext(body);

        Test.startTest();
        MetriportPatientWebhook.handleWebhook();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Expected 200 for non-patient event'
        );
    }

    // 🔹 Test: missing metaType → 400
    @IsTest
    static void testMissingMetaType() {
        String body = JSON.serialize(new Map<String, Object>{
            'id' => 'noMetaType'
        });

        setupRestContext(body);

        Test.startTest();
        MetriportPatientWebhook.handleWebhook();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Expected 400 when metaType is missing'
        );
    }

    // 🔹 Test: blank metaType → 400
    @IsTest
    static void testBlankMetaType() {
        String body = JSON.serialize(new Map<String, Object>{
            'metaType' => ''
        });

        setupRestContext(body);

        Test.startTest();
        MetriportPatientWebhook.handleWebhook();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Expected 400 when metaType is blank'
        );
    }
}