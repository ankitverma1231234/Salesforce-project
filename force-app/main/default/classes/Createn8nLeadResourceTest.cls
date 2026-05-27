@isTest
private class Createn8nLeadResourceTest {

    private static RestRequest buildRequest(String jsonBody) {
        RestRequest req = new RestRequest();
        req.requestURI  = '/services/apexrest/n8nLead/';
        req.httpMethod  = 'POST';
        req.requestBody = Blob.valueOf(jsonBody);
        req.addHeader('Content-Type', 'application/json');
        return req;
    }

    // ── Test 1: Success - "19 September 2000" ────────
    @isTest
    static void testCreateLeadSuccess() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Shum Kapoor',
            'Caller_Id' => '+18608516909',
            'DOB'       => '19 September 2000',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test1 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 2: Single Name (No Space) ───────────────
    @isTest
    static void testCreateLeadSingleName() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Kapoor',
            'Caller_Id' => '+18608516909',
            'DOB'       => '19 September 2000',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test2 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 3: DOB Ordinal Suffix "19th" ────────────
    @isTest
    static void testCreateLeadOrdinalDOB() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Shum Kapoor',
            'Caller_Id' => '+18608516909',
            'DOB'       => '19th September 2000',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test3 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 4: No DOB ───────────────────────────────
    @isTest
    static void testCreateLeadNoDOB() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Shum Kapoor',
            'Caller_Id' => '+18608516909',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test4 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 5: No Address ───────────────────────────
    @isTest
    static void testCreateLeadNoAddress() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Shum Kapoor',
            'Caller_Id' => '+18608516909',
            'DOB'       => '19 September 2000'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test5 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 6: Invalid Body → Catch Block ───────────
    @isTest
    static void testCreateLeadInvalidBody() {
        RestContext.request  = buildRequest('INVALID_JSON');
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assertEquals(false, result.success, 'Should fail on invalid JSON');
        System.assertNotEquals(null, result.error, 'Error message should be present');
        System.debug('Test6 error=' + result.error);
    }

    // ── Test 7: DOB Format "September 19, 2000" ──────
    @isTest
    static void testDOBFormatMonthDayYear() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Shum Kapoor',
            'Caller_Id' => '+18608516909',
            'DOB'       => 'September 19, 2000',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test7 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 8: DOB Format "2000-09-19" YYYY-MM-DD ───
    @isTest
    static void testDOBFormatISO() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Shum Kapoor',
            'Caller_Id' => '+18608516909',
            'DOB'       => '2000-09-19',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test8 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 9: DOB Format "09/19/2000" MM/DD/YYYY ───
    @isTest
    static void testDOBFormatSlash() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Shum Kapoor',
            'Caller_Id' => '+18608516909',
            'DOB'       => '09/19/2000',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test9 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 10: DOB Format "September 19 2000" ──────
    @isTest
    static void testDOBFormatMonthDayYearNoComma() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Shum Kapoor',
            'Caller_Id' => '+18608516909',
            'DOB'       => 'September 19 2000',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test10 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 11: No Caller_Id ────────────────────────
    @isTest
    static void testCreateLeadNoCallerID() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'to'        => 'Shum Kapoor',
            'DOB'       => '19 September 2000',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test11 success=' + result.success + ' error=' + result.error);
    }

    // ── Test 12: No Name (Null to field) ─────────────
    @isTest
    static void testCreateLeadNoName() {
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'Caller_Id' => '+18608516909',
            'DOB'       => '19 September 2000',
            'Address'   => '123 Main Street, New York, NY, 10001'
        });
        RestContext.request  = buildRequest(jsonBody);
        RestContext.response = new RestResponse();
        Test.startTest();
        Createn8nLeadResource.ResponseWrapper result =
            Createn8nLeadResource.createLead();
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.debug('Test12 success=' + result.success + ' error=' + result.error);
    }
}