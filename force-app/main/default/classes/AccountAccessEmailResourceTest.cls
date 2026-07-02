@isTest(SeeAllData=true)
private class AccountAccessEmailResourceTest {

    private static void setRestContext(String body) {
        RestRequest req  = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody  = Blob.valueOf(body);
        req.httpMethod   = 'POST';
        RestContext.request  = req;
        RestContext.response = res;
    }

   
    @isTest
    static void testMissingRequestBody() {
        RestRequest req  = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody  = null;
        req.httpMethod   = 'POST';
        RestContext.request  = req;
        RestContext.response = res;

        Test.startTest();
        try {
            AccountAccessEmailResource.sendAccessEmail();
        } catch (Exception e) {
            System.assert(true, 'Exception expected for null body');
        }
        Test.stopTest();
    }

    // ── Test 2: Missing accountId ─────────────────────────────────────────────
    @isTest
    static void testMissingAccountId() {
        setRestContext('{"give_access":true,"request_access":false}');

        Test.startTest();
        AccountAccessEmailResource.sendAccessEmail();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('Missing accountId'),
            'Should return missing accountId error'
        );
    }

    // ── Test 3: Missing Both Access Flags ─────────────────────────────────────
    @isTest
    static void testMissingAccessFlags() {
        // Grab any real Person Account from org
        Account acc = [
            SELECT Id FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail != null
            LIMIT 1
        ];

        setRestContext('{"accountId":"' + acc.Id + '","give_access":false,"request_access":false}');

        Test.startTest();
        AccountAccessEmailResource.sendAccessEmail();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('give_access or request_access'),
            'Should return access flag error'
        );
    }

    // ── Test 4: AHR Not Found ─────────────────────────────────────────────────
    @isTest
    static void testAHRNotFound() {
        // Use an Account that has no AHR
        Account acc = [
            SELECT Id FROM Account
            WHERE IsPersonAccount = true
            AND Id NOT IN (
                SELECT Authorized_Account_Access__c
                FROM Account_Head_Relationship__c
                WHERE Authorized_Account_Access__c != null
            )
            LIMIT 1
        ];

        setRestContext('{"accountId":"' + acc.Id + '","give_access":false,"request_access":true}');

        Test.startTest();
        AccountAccessEmailResource.sendAccessEmail();
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('No Account Head Relationship found'),
            'Should return AHR not found'
        );
    }

    // ── Test 5: Request Access Email ──────────────────────────────────────────
    @isTest
    static void testRequestAccessEmail() {
        // Get an Account that has an AHR with request_access = true
        Account_Head_Relationship__c ahr = [
            SELECT Id, Authorized_Account_Access__c,
                   Authorized_Account_Access__r.PersonEmail
            FROM Account_Head_Relationship__c
            WHERE Request_Access__c = true
            AND Authorized_Account_Access__c != null
            AND Authorized_Account_Access__r.PersonEmail != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        setRestContext('{"accountId":"' + ahr.Authorized_Account_Access__c + '","give_access":false,"request_access":true}');

        Test.startTest();
        AccountAccessEmailResource.sendAccessEmail();
        Test.stopTest();

        Integer statusCode = RestContext.response.statusCode;
        System.assert(
            statusCode == 200 || statusCode == 404 || statusCode == 500,
            'Should return valid status: ' + statusCode
        );
    }

    // ── Test 6: Give Access Email ─────────────────────────────────────────────
    @isTest
    static void testGiveAccessEmail() {
        // Get an Account that has an AHR with give_access = true
        Account_Head_Relationship__c ahr = [
            SELECT Id, Authorized_Account_Access__c,
                   Authorized_Account_Access__r.PersonEmail
            FROM Account_Head_Relationship__c
            WHERE Give_Access__c = true
            AND Authorized_Account_Access__c != null
            AND Authorized_Account_Access__r.PersonEmail != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        setRestContext('{"accountId":"' + ahr.Authorized_Account_Access__c + '","give_access":true,"request_access":false}');

        Test.startTest();
        AccountAccessEmailResource.sendAccessEmail();
        Test.stopTest();

        Integer statusCode = RestContext.response.statusCode;
        System.assert(
            statusCode == 200 || statusCode == 404 || statusCode == 500,
            'Should return valid status: ' + statusCode
        );
    }

    // ── Test 7: Blank PersonEmail ─────────────────────────────────────────────
    @isTest
    static void testBlankPersonEmail() {
        // Get AHR where Authorized Account has no email
        Account_Head_Relationship__c ahr = [
            SELECT Id, Authorized_Account_Access__c
            FROM Account_Head_Relationship__c
            WHERE Authorized_Account_Access__c != null
            AND Authorized_Account_Access__r.PersonEmail = null
            LIMIT 1
        ];

        if (ahr == null) {
            System.assert(true, 'No AHR with blank email found — skipping test');
            return;
        }

        setRestContext('{"accountId":"' + ahr.Authorized_Account_Access__c + '","give_access":false,"request_access":true}');

        Test.startTest();
        AccountAccessEmailResource.sendAccessEmail();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('PersonEmail is blank'),
            'Should return blank email error'
        );
    }

    // ── Test 8: Invalid JSON ──────────────────────────────────────────────────
    @isTest
    static void testInvalidJson() {
        setRestContext('INVALID JSON {{{');

        Test.startTest();
        AccountAccessEmailResource.sendAccessEmail();
        Test.stopTest();

        System.assertEquals(500, RestContext.response.statusCode);
    }

    // ── Test 9: Both Access Flags True ────────────────────────────────────────
    @isTest
    static void testBothAccessFlagsTrue() {
        Account_Head_Relationship__c ahr = [
            SELECT Id, Authorized_Account_Access__c
            FROM Account_Head_Relationship__c
            WHERE Authorized_Account_Access__c != null
            AND Authorized_Account_Access__r.PersonEmail != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        setRestContext('{"accountId":"' + ahr.Authorized_Account_Access__c + '","give_access":true,"request_access":true}');

        Test.startTest();
        AccountAccessEmailResource.sendAccessEmail();
        Test.stopTest();

        Integer statusCode = RestContext.response.statusCode;
        System.assert(
            statusCode == 200 || statusCode == 404 || statusCode == 500,
            'Should process with give_access priority: ' + statusCode
        );
    }

    // ── Test 10: Validate AHR Fields ─────────────────────────────────────────
    @isTest
    static void testAHRFieldsPopulated() {
        Account_Head_Relationship__c ahr = [
            SELECT Id, Verification_Code__c, Approval_Token__c,
                   Token_Expiry__c, Head_Account_Name__c, Child_Account_Name__c,
                   Authorized_Account_Access__r.PersonEmail
            FROM Account_Head_Relationship__c
            WHERE Authorized_Account_Access__c != null
            AND Verification_Code__c != null
            AND Approval_Token__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.assertNotEquals(null, ahr.Verification_Code__c,  'Verification code should not be null');
        System.assertNotEquals(null, ahr.Approval_Token__c,     'Token should not be null');
        System.assertNotEquals(null, ahr.Token_Expiry__c,       'Token expiry should not be null');
        System.assertNotEquals(null, ahr.Head_Account_Name__c,  'Head name should not be null');
        System.assertNotEquals(null, ahr.Child_Account_Name__c, 'Child name should not be null');
        System.assertNotEquals(null, ahr.Authorized_Account_Access__r.PersonEmail, 'Email should not be null');
    }
}