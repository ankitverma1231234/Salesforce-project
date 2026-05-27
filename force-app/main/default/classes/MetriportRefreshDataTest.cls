@isTest(SeeAllData=true)
public class MetriportRefreshDataTest {
    
    private static Account getOrCreatePersonAccount() {
        List<Account> existing = [
            SELECT Id, Metriport_Patient_Id__c, PersonEmail, PersonMobilePhone
            FROM   Account
            WHERE  IsPersonAccount    = true
            AND    PersonEmail        != null
            AND    PersonMobilePhone  != null
            LIMIT  1
        ];

        if (!existing.isEmpty()) {
            if (String.isBlank(existing[0].Metriport_Patient_Id__c)) {
                existing[0].Metriport_Patient_Id__c = 'MTRPTEST001';
                update existing[0];
            }
            return existing[0];
        }

        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account testAcc = new Account(
            FirstName               = 'Existing',
            LastName                = 'Test',
            RecordTypeId            = personAccountRT,
            PersonEmail             = 'existing.test@example.com',
            PersonMobilePhone       = '5551234567',
            Metriport_Patient_Id__c = 'MTRPTEST001'
        );
        insert testAcc;
        return testAcc;
    }

    private static Account getOrCreatePersonAccountNoMetriportId() {
        List<Account> existing = [
            SELECT Id, Metriport_Patient_Id__c, PersonEmail, PersonMobilePhone
            FROM   Account
            WHERE  IsPersonAccount          = true
            AND    PersonEmail             != null
            AND    PersonMobilePhone       != null
            AND    Metriport_Patient_Id__c  = null
            LIMIT  1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account testAcc = new Account(
            FirstName         = 'NoMetriport',
            LastName          = 'Test',
            RecordTypeId      = personAccountRT,
            PersonEmail       = 'no.metriport@example.com',
            PersonMobilePhone = '5559876543'
            // Metriport_Patient_Id__c intentionally left blank
        );
        insert testAcc;
        return testAcc;
    }

    private static void setupRestContext(String bodyJson) {
        RestRequest req  = new RestRequest();
        req.requestURI   = '/services/apexrest/metripoint/refresh/';
        req.httpMethod   = 'POST';
        if (bodyJson != null) {
            req.requestBody = Blob.valueOf(bodyJson);
        }
        RestContext.request  = req;
        RestContext.response = new RestResponse();
    }


    private class MetriportMock implements HttpCalloutMock {
        private Integer statusCode;
        MetriportMock(Integer statusCode) { this.statusCode = statusCode; }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody('{}');
            return res;
        }
    }

    @isTest
    static void testHandleRefresh_Success() {
        Account acc = getOrCreatePersonAccount();

        setupRestContext('{"patientId":"' + acc.Id + '"}');
        // Mock needed because @future callout runs within Test.startTest/stopTest
        Test.setMock(HttpCalloutMock.class, new MetriportMock(200));

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest(); // @future executes here

        RestResponse res = RestContext.response;
        System.assertEquals(202, res.statusCode,
            'Expected HTTP 202 Accepted — async refresh queued');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(true,    body.get('success'),   'success flag should be true');
        System.assertEquals(acc.Id,  body.get('patientId'), 'patientId should echo back');
        System.assertEquals(
            'Refresh request accepted. Data will be updated shortly.',
            body.get('message'),
            'message should reflect async acceptance'
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 2 – Missing request body → 400 MISSING_BODY
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testHandleRefresh_MissingBody() {
        setupRestContext(null);

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode, 'Expected HTTP 400 for missing body');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,          body.get('success'));
        System.assertEquals('MISSING_BODY', body.get('errorCode'));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 3 – Empty body (zero-length blob) → 400 MISSING_BODY
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testHandleRefresh_EmptyBody() {
        RestRequest req  = new RestRequest();
        req.requestURI   = '/services/apexrest/metripoint/refresh/';
        req.httpMethod   = 'POST';
        req.requestBody  = Blob.valueOf(''); // size() == 0
        RestContext.request  = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode, 'Expected HTTP 400 for empty body');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,          body.get('success'));
        System.assertEquals('MISSING_BODY', body.get('errorCode'));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 4 – patientId field present but blank → 400 MISSING_PATIENT_ID
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testHandleRefresh_MissingPatientId() {
        setupRestContext('{"patientId":""}');

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode, 'Expected HTTP 400 for blank patientId');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,                body.get('success'));
        System.assertEquals('MISSING_PATIENT_ID', body.get('errorCode'));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 5 – patientId null in JSON → 400 MISSING_PATIENT_ID
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testHandleRefresh_NullPatientId() {
        setupRestContext('{"patientId":null}');

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode, 'Expected HTTP 400 for null patientId');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,                body.get('success'));
        System.assertEquals('MISSING_PATIENT_ID', body.get('errorCode'));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 6 – patientId with invalid characters → 400 INVALID_PATIENT_ID
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testHandleRefresh_InvalidPatientIdFormat() {
        setupRestContext('{"patientId":"BAD-ID!!!"}');

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode, 'Expected HTTP 400 for invalid patientId format');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,                body.get('success'));
        System.assertEquals('INVALID_PATIENT_ID', body.get('errorCode'));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 7 – patientId wrong length → 400 INVALID_PATIENT_ID
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testHandleRefresh_InvalidPatientIdLength() {
        setupRestContext('{"patientId":"ABC123"}'); // only 6 chars

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode, 'Expected HTTP 400 for wrong-length patientId');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,                body.get('success'));
        System.assertEquals('INVALID_PATIENT_ID', body.get('errorCode'));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 8 – Valid 15-char format but no matching Account → 404 PATIENT_NOT_FOUND
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testHandleRefresh_PatientNotFound_15Char() {
        setupRestContext('{"patientId":"001000000000001"}');

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(404, res.statusCode, 'Expected HTTP 404 for non-existent account');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,             body.get('success'));
        System.assertEquals('PATIENT_NOT_FOUND', body.get('errorCode'));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 9 – Valid 18-char format but no matching Account → 404 PATIENT_NOT_FOUND
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testHandleRefresh_PatientNotFound_18Char() {
        setupRestContext('{"patientId":"001000000000001AAA"}');

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(404, res.statusCode, 'Expected HTTP 404 for non-existent 18-char account');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,             body.get('success'));
        System.assertEquals('PATIENT_NOT_FOUND', body.get('errorCode'));
    }

    @isTest
    static void testHandleRefresh_MissingMetriportId() {
        Account acc = getOrCreatePersonAccountNoMetriportId();

        setupRestContext('{"patientId":"' + acc.Id + '"}');

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(422, res.statusCode,
            'Expected HTTP 422 when Metriport_Patient_Id__c is blank');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,                  body.get('success'));
        System.assertEquals('MISSING_METRIPORT_ID', body.get('errorCode'));
    }

    @isTest
    static void testHandleRefresh_InvalidJson() {
        setupRestContext('NOT_VALID_JSON');

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode, 'Expected HTTP 400 for malformed JSON');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,          body.get('success'));
        System.assertEquals('INVALID_JSON', body.get('errorCode'));
    }

    @isTest
    static void testHandleRefresh_TruncatedJson() {
        setupRestContext('{"patientId":'); // incomplete JSON

        Test.startTest();
        MetriportRefershData.handleRefresh();
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(400, res.statusCode, 'Expected HTTP 400 for truncated JSON');

        Map<String, Object> body =
            (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        System.assertEquals(false,          body.get('success'));
        System.assertEquals('INVALID_JSON', body.get('errorCode'));
    }
}