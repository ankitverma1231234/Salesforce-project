@isTest(SeeAllData=true)
public class AccountHeadLinkResourceTest {

    // ── Unique suffix per test run to avoid SeeAllData conflicts ──────────────
    private static String uid() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static Id getPersonAccountRecordTypeId() {
        return [
            SELECT Id FROM RecordType
            WHERE  SObjectType = 'Account'
            AND    IsPersonType = true
            LIMIT  1
        ].Id;
    }

    private static Account createPersonAccount(
        String firstName, String lastName,
        String email,     String phone
    ) {
        Account a = new Account(
            RecordTypeId      = getPersonAccountRecordTypeId(),
            FirstName         = firstName,
            LastName          = lastName,
            PersonEmail       = email,
            PersonMobilePhone = phone
        );

        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave        = true;
        dml.duplicateRuleHeader.runAsCurrentUser = true;

        Database.SaveResult sr = Database.insert(a, dml);
        if (!sr.isSuccess()) {
            throw new DmlException(
                'createPersonAccount failed: ' + sr.getErrors()[0].getMessage()
            );
        }
        return a;
    }

    // ── Creates a plain junction (no access flags) ─────────────────────────────
    private static Account_Head_Relationship__c createJunction(Id parentId, Id childId) {
        Account_Head_Relationship__c j = new Account_Head_Relationship__c(
            Member_Account__c            = parentId,
            Authorized_Account_Access__c = childId,
            Give_Access__c               = false,
            Request_Access__c            = false
        );
        insert j;
        return j;
    }

    // ── Creates a give_access junction ────────────────────────────────────────
    private static Account_Head_Relationship__c createGiveJunction(Id parentId, Id childId) {
        Account_Head_Relationship__c j = new Account_Head_Relationship__c(
            Member_Account__c            = parentId,
            Authorized_Account_Access__c = childId,
            Give_Access__c               = true,
            Request_Access__c            = false
        );
        insert j;
        return j;
    }

    // ── Creates a request_access junction ────────────────────────────────────
    private static Account_Head_Relationship__c createRequestJunction(Id parentId, Id childId) {
        Account_Head_Relationship__c j = new Account_Head_Relationship__c(
            Member_Account__c            = parentId,
            Authorized_Account_Access__c = childId,
            Give_Access__c               = false,
            Request_Access__c            = true
        );
        insert j;
        return j;
    }

    private static RestResponse setupRestContext(String jsonBody) {
        RestRequest req  = new RestRequest();
        req.requestURI   = '/services/apexrest/AccountHeadLink/';
        req.httpMethod   = 'POST';
        req.requestBody  = Blob.valueOf(jsonBody);
        RestContext.request = req;

        RestResponse res = new RestResponse();
        RestContext.response = res;
        return res;
    }

    private static Map<String, Object> parseResponse(RestResponse res) {
        return (Map<String, Object>) JSON.deserializeUntyped(
            res.responseBody.toString()
        );
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 1 — Structural / validation tests
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testMissingParentBlock_Returns400() {
        RestResponse res = setupRestContext(
            '{"children":[{"firstName":"John","lastName":"Doe",' +
            '"email":"j@t.com","mobilePhone":"1234567890"}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        Map<String, Object> body = parseResponse(res);
        System.assertEquals(false, body.get('success'));
        System.assertEquals(
            'parent block and at least one child are required.',
            body.get('message')
        );
    }

    @isTest
    static void testEmptyChildrenList_Returns400() {
        String  u      = uid();
        Account parent = createPersonAccount('Head', 'Empty' + u,
                                             'head.empty.' + u + '@test.com', u.left(10));

        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},"children":[]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        Map<String, Object> body = parseResponse(res);
        System.assertEquals(false, body.get('success'));
    }

    @isTest
    static void testBlankParentAccountId_Returns400() {
        RestResponse res = setupRestContext(
            '{"parent":{"accountId":""},"children":[{"firstName":"John",' +
            '"lastName":"Doe","email":"j@t.com","mobilePhone":"1234567890"}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        Map<String, Object> body = parseResponse(res);
        System.assertEquals('parent accountId is required.', body.get('message'));
    }

    @isTest
    static void testNullParentInPayload_Returns400() {
        RestResponse res = setupRestContext(
            '{"parent":null,"children":[{"firstName":"John","lastName":"Doe",' +
            '"email":"j@t.com","mobilePhone":"1234567890"}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        Map<String, Object> body = parseResponse(res);
        System.assertEquals(false, body.get('success'));
    }

    @isTest
    static void testChildValidationError_MissingFields_Returns400() {
        String  u      = uid();
        Account parent = createPersonAccount('Head', 'Val' + u,
                                             'head.val.' + u + '@test.com', u.left(10));

        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"John","lastName":"",' +
            '"email":"j@t.com","mobilePhone":""}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        Map<String, Object> body = parseResponse(res);
        System.assertEquals('Child validation failed.', body.get('message'));

        List<Object> results = (List<Object>) body.get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(false, r.get('success'));
        System.assertEquals('email and mobilePhone are required.', r.get('message'));
    }

    @isTest
    static void testParentAccountNotFound_Returns404() {
        String fakeId = '001000000000001AAA';
        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + fakeId + '"},' +
            '"children":[{"firstName":"John","lastName":"Doe",' +
            '"email":"j@t.com","mobilePhone":"1234567890"}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(404, res.statusCode);
        Map<String, Object> body = parseResponse(res);
        System.assertEquals(false, body.get('success'));
        System.assertEquals('Parent Account not found.', body.get('message'));
    }

    @isTest
    static void testChildAccountNotFound_Returns200WithFailureResult() {
        String  u      = uid();
        Account parent = createPersonAccount('Head', 'NF' + u,
                                             'head.nf.' + u + '@test.com', u.left(10));

        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Ghost' + u + '","lastName":"Child' + u + '",' +
            '"email":"ghost.' + u + '@nowhere.com","mobilePhone":"' + u.left(10) + '9"}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        Map<String, Object> body    = parseResponse(res);
        List<Object>        results = (List<Object>) body.get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(false, r.get('success'));
        System.assertEquals(
            'Member not found with the provided email address and Phone Number.',
            r.get('message')
        );
    }

    @isTest
    static void testParentAndChildSameAccount_Returns200WithFailureResult() {
        String  u   = uid();
        Account acc = createPersonAccount('Same' + u, 'Acct' + u,
                                          'same.' + u + '@test.com', u.left(10));

        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + acc.Id + '"},' +
            '"children":[{"firstName":"Same' + u + '","lastName":"Acct' + u + '",' +
            '"email":"same.' + u + '@test.com","mobilePhone":"' + u.left(10) + '"}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        Map<String, Object> body    = parseResponse(res);
        List<Object>        results = (List<Object>) body.get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size(),
                            'Expected 1 result | Response: ' + res.responseBody.toString());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(false, r.get('success'));
        System.assertEquals('Parent and Child cannot be the same Account.', r.get('message'));
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 2 — Plain link (no give/request flags)
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testPlainLinkCreated_Returns200WithRelationshipId() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'Creator' + u,
                                             'head.creator.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'New' + u,
                                             'child.new.' + u + '@test.com', (u + '1').left(10));

        // No give_access or request_access — plain record
        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Child' + u + '","lastName":"New' + u + '",' +
            '"email":"child.new.' + u + '@test.com","mobilePhone":"' + (u + '1').left(10) + '",' +
            '"relationship":"Spouse","portal_status":"Pending"}]}';

        RestResponse res = setupRestContext(payload);

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        Map<String, Object> body    = parseResponse(res);
        List<Object>        results = (List<Object>) body.get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size(),
                            'Expected 1 result | Response: ' + res.responseBody.toString());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true,  r.get('success'));
        System.assertEquals('Account Head Relationship created successfully.', r.get('message'));
        // Plain record → relationshipId is populated, give/request rel ids are null
        System.assertNotEquals(null, r.get('relationshipId'),     'relationshipId must be set for plain record');
        System.assertEquals(null,    r.get('give_access_rel_id'), 'give_access_rel_id must be null for plain record');
        System.assertEquals(null,    r.get('request_access_rel_id'), 'request_access_rel_id must be null for plain record');

        List<Account_Head_Relationship__c> junctions = [
            SELECT Id, Give_Access__c, Request_Access__c
            FROM   Account_Head_Relationship__c
            WHERE  Member_Account__c            = :parent.Id
            AND    Authorized_Account_Access__c = :child.Id
        ];
        System.assertEquals(1, junctions.size(), '1 plain junction record must exist in DB');
        System.assertEquals(false, junctions[0].Give_Access__c);
        System.assertEquals(false, junctions[0].Request_Access__c);
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 3 — give_access record creation
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGiveAccessRecord_CreatedSuccessfully() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'Give' + u,
                                             'head.give.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'Give' + u,
                                             'child.give.' + u + '@test.com', (u + '2').left(10));

        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Child' + u + '","lastName":"Give' + u + '",' +
            '"email":"child.give.' + u + '@test.com","mobilePhone":"' + (u + '2').left(10) + '",' +
            '"give_access":true,"request_access":false}]}';

        RestResponse res = setupRestContext(payload);

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertEquals(1, results.size(),
                            'Expected 1 result | Response: ' + res.responseBody.toString());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true, r.get('success'));
        System.assertEquals('Account Head Relationship created successfully.', r.get('message'));
        System.assertNotEquals(null, r.get('give_access_rel_id'),    'give_access_rel_id must be set');
        System.assertEquals(null,    r.get('request_access_rel_id'), 'request_access_rel_id must be null');
        System.assertEquals(true,    r.get('give_access'));

        List<Account_Head_Relationship__c> junctions = [
            SELECT Id, Give_Access__c, Request_Access__c
            FROM   Account_Head_Relationship__c
            WHERE  Member_Account__c            = :parent.Id
            AND    Authorized_Account_Access__c = :child.Id
            AND    Give_Access__c               = true
        ];
        System.assertEquals(1, junctions.size(), 'One Give_Access record must exist in DB');
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 4 — request_access record creation
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testRequestAccessRecord_CreatedSuccessfully() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'Req' + u,
                                             'head.req.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'Req' + u,
                                             'child.req.' + u + '@test.com', (u + '3').left(10));

        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Child' + u + '","lastName":"Req' + u + '",' +
            '"email":"child.req.' + u + '@test.com","mobilePhone":"' + (u + '3').left(10) + '",' +
            '"give_access":false,"request_access":true}]}';

        RestResponse res = setupRestContext(payload);

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertEquals(1, results.size(),
                            'Expected 1 result | Response: ' + res.responseBody.toString());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true, r.get('success'));
        System.assertEquals('Account Head Relationship created successfully.', r.get('message'));
        System.assertEquals(null,    r.get('give_access_rel_id'),       'give_access_rel_id must be null');
        System.assertNotEquals(null, r.get('request_access_rel_id'),    'request_access_rel_id must be set');
        System.assertEquals(true,    r.get('request_access'));

        List<Account_Head_Relationship__c> junctions = [
            SELECT Id, Give_Access__c, Request_Access__c
            FROM   Account_Head_Relationship__c
            WHERE  Member_Account__c            = :parent.Id
            AND    Authorized_Account_Access__c = :child.Id
            AND    Request_Access__c            = true
        ];
        System.assertEquals(1, junctions.size(), 'One Request_Access record must exist in DB');
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 5 — Both give_access AND request_access → 2 separate records
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testBothAccessFlags_Creates2SeparateRecords() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'Both' + u,
                                             'head.both.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'Both' + u,
                                             'child.both.' + u + '@test.com', (u + '4').left(10));

        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Child' + u + '","lastName":"Both' + u + '",' +
            '"email":"child.both.' + u + '@test.com","mobilePhone":"' + (u + '4').left(10) + '",' +
            '"give_access":true,"request_access":true}]}';

        RestResponse res = setupRestContext(payload);

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');

        // 2 separate results — one for give, one for request
        System.assertEquals(2, results.size(),
                            'Both give and request should produce 2 separate results | ' +
                            res.responseBody.toString());

        Integer giveCount    = 0;
        Integer requestCount = 0;
        for (Object o : results) {
            Map<String, Object> r = (Map<String, Object>) o;
            System.assertEquals(true, r.get('success'));
            System.assertEquals('Account Head Relationship created successfully.', r.get('message'));
            if (r.get('give_access_rel_id')    != null) giveCount++;
            if (r.get('request_access_rel_id') != null) requestCount++;
        }
        System.assertEquals(1, giveCount,    'One give_access result expected');
        System.assertEquals(1, requestCount, 'One request_access result expected');

        // Verify 2 DB records exist for the same parent-child pair
        List<Account_Head_Relationship__c> junctions = [
            SELECT Id, Give_Access__c, Request_Access__c
            FROM   Account_Head_Relationship__c
            WHERE  Member_Account__c            = :parent.Id
            AND    Authorized_Account_Access__c = :child.Id
            ORDER BY Give_Access__c DESC
        ];
        System.assertEquals(2, junctions.size(), '2 junction records must exist in DB');
        System.assertEquals(true,  junctions[0].Give_Access__c);
        System.assertEquals(false, junctions[0].Request_Access__c);
        System.assertEquals(false, junctions[1].Give_Access__c);
        System.assertEquals(true,  junctions[1].Request_Access__c);
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 6 — "Already exists" scenarios
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testGiveAlreadyExists_ReturnsAlreadyExists() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'GiveEx' + u,
                                             'head.giveex.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'GiveEx' + u,
                                             'child.giveex.' + u + '@test.com', (u + '5').left(10));

        Account_Head_Relationship__c existing = createGiveJunction(parent.Id, child.Id);

        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Child' + u + '","lastName":"GiveEx' + u + '",' +
            '"email":"child.giveex.' + u + '@test.com","mobilePhone":"' + (u + '5').left(10) + '",' +
            '"give_access":true,"request_access":false}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertEquals(1, results.size(),
                            'Expected 1 result | Response: ' + res.responseBody.toString());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true,        r.get('success'));
        System.assertEquals('Relationship already exists.', r.get('message'));
        System.assertEquals(existing.Id, r.get('give_access_rel_id'));
    }

    @isTest
    static void testRequestAlreadyExists_ReturnsAlreadyExists() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'ReqEx' + u,
                                             'head.reqex.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'ReqEx' + u,
                                             'child.reqex.' + u + '@test.com', (u + '6').left(10));

        Account_Head_Relationship__c existing = createRequestJunction(parent.Id, child.Id);

        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Child' + u + '","lastName":"ReqEx' + u + '",' +
            '"email":"child.reqex.' + u + '@test.com","mobilePhone":"' + (u + '6').left(10) + '",' +
            '"give_access":false,"request_access":true}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertEquals(1, results.size(),
                            'Expected 1 result | Response: ' + res.responseBody.toString());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true,        r.get('success'));
        System.assertEquals('Relationship already exists.', r.get('message'));
        System.assertEquals(existing.Id, r.get('request_access_rel_id'));
    }

    @isTest
    static void testBothAlreadyExist_ReturnsAlreadyExists() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'BothEx' + u,
                                             'head.bothex.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'BothEx' + u,
                                             'child.bothex.' + u + '@test.com', (u + '7').left(10));

        Account_Head_Relationship__c giveRec    = createGiveJunction(parent.Id, child.Id);
        Account_Head_Relationship__c requestRec = createRequestJunction(parent.Id, child.Id);

        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Child' + u + '","lastName":"BothEx' + u + '",' +
            '"email":"child.bothex.' + u + '@test.com","mobilePhone":"' + (u + '7').left(10) + '",' +
            '"give_access":true,"request_access":true}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');
        // Both already exist → single "already exists" result
        System.assertEquals(1, results.size(),
                            'Expected 1 already-exists result | Response: ' + res.responseBody.toString());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true,          r.get('success'));
        System.assertEquals('Relationship already exists.', r.get('message'));
        System.assertEquals(giveRec.Id,    r.get('give_access_rel_id'));
        System.assertEquals(requestRec.Id, r.get('request_access_rel_id'));
    }

    @isTest
    static void testGiveExistsRequestMissing_CreatesOnlyRequestRecord() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'Partial' + u,
                                             'head.partial.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'Partial' + u,
                                             'child.partial.' + u + '@test.com', (u + '8').left(10));

        // Give record already exists
        Account_Head_Relationship__c giveRec = createGiveJunction(parent.Id, child.Id);

        // Portal sends both flags — give already exists, request doesn't
        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Child' + u + '","lastName":"Partial' + u + '",' +
            '"email":"child.partial.' + u + '@test.com","mobilePhone":"' + (u + '8').left(10) + '",' +
            '"give_access":true,"request_access":true}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');

        // Give already exists (skipped), Request is new → only 1 result for the newly created request record
        System.assertEquals(1, results.size(),
                            'Expected 1 new request result | Response: ' + res.responseBody.toString());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true,  r.get('success'));
        System.assertEquals('Account Head Relationship created successfully.', r.get('message'));
        System.assertNotEquals(null, r.get('request_access_rel_id'), 'request_access_rel_id must be set');
        System.assertEquals(null,    r.get('give_access_rel_id'),    'give_access_rel_id must be null (was pre-existing)');

        // Verify both records now exist in DB
        List<Account_Head_Relationship__c> junctions = [
            SELECT Id, Give_Access__c, Request_Access__c
            FROM   Account_Head_Relationship__c
            WHERE  Member_Account__c            = :parent.Id
            AND    Authorized_Account_Access__c = :child.Id
        ];
        System.assertEquals(2, junctions.size(), '2 records must exist after partial creation');
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 7 — Multiple children mixed results
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testMultipleChildren_MixedResults() {
        String  u      = uid();
        Account parent = createPersonAccount('Head'  + u, 'Multi'    + u,
                                             'head.multi.' + u + '@test.com', u.left(10));
        Account child1 = createPersonAccount('Alpha' + u, 'MultiOne' + u,
                                             'alpha.m1.'   + u + '@test.com', (u + '3').left(10));
        Account child2 = createPersonAccount('Beta'  + u, 'MultiTwo' + u,
                                             'beta.m2.'    + u + '@test.com', (u + '4').left(10));

        // child2 already has a give_access record
        createGiveJunction(parent.Id, child2.Id);

        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},"children":['
            // child1 → new give_access record
            + '{"firstName":"Alpha' + u + '","lastName":"MultiOne' + u + '",'
            + '"email":"alpha.m1.' + u + '@test.com","mobilePhone":"' + (u + '3').left(10) + '",'
            + '"give_access":true,"request_access":false},'
            // child2 → give already exists → "already exists"
            + '{"firstName":"Beta'  + u + '","lastName":"MultiTwo' + u + '",'
            + '"email":"beta.m2.'  + u + '@test.com","mobilePhone":"' + (u + '4').left(10) + '",'
            + '"give_access":true,"request_access":false},'
            // ghost → not found
            + '{"firstName":"Ghost' + u + '","lastName":"Nobody' + u + '",'
            + '"email":"ghost.'     + u + '@nowhere.com","mobilePhone":"' + (u + '5').left(10) + '",'
            + '"give_access":true,"request_access":false}'
            + ']}';

        RestResponse res = setupRestContext(payload);

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode,
                            'Expected 200 | Response: ' + res.responseBody.toString());

        List<Object> results = (List<Object>) parseResponse(res).get('results');

        Integer createdCount  = 0;
        Integer existsCount   = 0;
        Integer notFoundCount = 0;

        for (Object o : results) {
            Map<String, Object> r   = (Map<String, Object>) o;
            String              msg = (String) r.get('message');
            if (msg == 'Account Head Relationship created successfully.') createdCount++;
            else if (msg == 'Relationship already exists.')               existsCount++;
            else if (msg == 'Member not found with the provided email address and Phone Number.') notFoundCount++;
        }

        System.assertEquals(1, createdCount,  'child1 give record should be created');
        System.assertEquals(1, existsCount,   'child2 give already exists');
        System.assertEquals(1, notFoundCount, 'ghost child should not be found');
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 8 — Flat standalone-delete  { account_headrelationshipid, is_delete }
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testFlatDelete_ValidId_Queued_Returns200() {
        String  u      = uid();
        Account parent = createPersonAccount('FDHead' + u, 'FD' + u,
                                             'fd.head.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('FDChild' + u, 'FD' + u,
                                             'fd.child.' + u + '@test.com', (u + '6').left(10));
        Account_Head_Relationship__c jr = createJunction(parent.Id, child.Id);

        RestResponse res = setupRestContext(
            '{"account_headrelationshipid":"' + jr.Id + '","is_delete":true}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode,
                            'Flat delete should return 200 | ' + res.responseBody.toString());

        Map<String, Object> body = parseResponse(res);
        System.assertEquals(true,                   body.get('success'));
        System.assertEquals('Processed successfully.', body.get('message'));

        List<Object> results = (List<Object>) body.get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true,               r.get('success'));
        System.assertEquals('Queued for deletion.', r.get('message'));
        System.assertEquals(jr.Id,              r.get('relationshipId'));

        List<Account_Head_Relationship__c> remaining = [
            SELECT Id FROM Account_Head_Relationship__c WHERE Id = :jr.Id
        ];
        System.assertEquals(0, remaining.size(),
                            'Junction record should have been deleted by the Queueable');
    }

    @isTest
    static void testFlatDelete_BlankId_Returns400() {
        RestResponse res = setupRestContext(
            '{"account_headrelationshipid":"","is_delete":true}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        Map<String, Object> body = parseResponse(res);
        System.assertEquals(false, body.get('success'));
        System.assertEquals(
            'account_headrelationshipid is required for delete.',
            body.get('message')
        );
    }

    @isTest
    static void testFlatDelete_IsDeleteFalse_FallsThroughToLinkValidation() {
        RestResponse res = setupRestContext(
            '{"account_headrelationshipid":"a4Fbf00000df7omEAA","is_delete":false}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        Map<String, Object> body = parseResponse(res);
        System.assertEquals(false, body.get('success'));
        System.assertEquals(
            'parent block and at least one child are required.',
            body.get('message')
        );
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 9 — Delete via children array  (is_delete inside children block)
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testChildDelete_ValidId_QueuedSuccessfully() {
        String  u      = uid();
        Account parent = createPersonAccount('CDHead' + u, 'CD' + u,
                                             'cd.head.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('CDChild' + u, 'CD' + u,
                                             'cd.child.' + u + '@test.com', (u + '7').left(10));
        Account_Head_Relationship__c jr = createJunction(parent.Id, child.Id);

        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},"children":[' +
            '{"account_headrelationshipid":"' + jr.Id + '","is_delete":true}]}';

        RestResponse res = setupRestContext(payload);

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode,
                            'Child delete should return 200 | ' + res.responseBody.toString());

        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true,               r.get('success'));
        System.assertEquals('Queued for deletion.', r.get('message'));

        List<Account_Head_Relationship__c> remaining = [
            SELECT Id FROM Account_Head_Relationship__c WHERE Id = :jr.Id
        ];
        System.assertEquals(0, remaining.size(), 'Junction should be deleted by Queueable');
    }

    @isTest
    static void testChildDelete_MissingRelationshipId_Returns400() {
        String  u      = uid();
        Account parent = createPersonAccount('CDMHead' + u, 'CDM' + u,
                                             'cdm.head.' + u + '@test.com', u.left(10));

        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},"children":[' +
            '{"is_delete":true}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(false, r.get('success'));
        System.assertEquals(
            'account_headrelationshipid is required for delete.',
            r.get('message')
        );
    }

    @isTest
    static void testMixedLinkAndDelete_SameRequest() {
        String  u      = uid();
        Account parent  = createPersonAccount('MixHead' + u, 'Mix' + u,
                                              'mix.head.' + u + '@test.com', u.left(10));
        Account child   = createPersonAccount('MixChild' + u, 'Link' + u,
                                              'mix.child.' + u + '@test.com', (u + '8').left(10));
        Account childDel = createPersonAccount('MixDel' + u, 'Del' + u,
                                               'mix.del.' + u + '@test.com', (u + '9').left(10));
        Account_Head_Relationship__c jr = createJunction(parent.Id, childDel.Id);

        // Link child (no flags = plain record), delete childDel
        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},"children":['
            + '{"firstName":"MixChild' + u + '","lastName":"Link' + u + '",'
            + '"email":"mix.child.' + u + '@test.com","mobilePhone":"' + (u + '8').left(10) + '"},'
            + '{"account_headrelationshipid":"' + jr.Id + '","is_delete":true}'
            + ']}';

        RestResponse res = setupRestContext(payload);

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode,
                            'Mixed request should return 200 | ' + res.responseBody.toString());

        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(2, results.size(), 'Expected 1 link + 1 delete result');

        Integer createdCount = 0;
        Integer deletedCount = 0;
        for (Object o : results) {
            Map<String, Object> r   = (Map<String, Object>) o;
            String              msg = (String) r.get('message');
            if (msg == 'Account Head Relationship created successfully.') createdCount++;
            if (msg == 'Queued for deletion.')                            deletedCount++;
        }
        System.assertEquals(1, createdCount, 'One link should be created');
        System.assertEquals(1, deletedCount, 'One delete should be queued');
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 10 — Phone normalisation
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testPhoneNormalization_FormattedPhone_StillMatches() {
        String  u      = uid();
        Account parent = createPersonAccount('PhHead' + u, 'Ph' + u,
                                             'ph.head.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('PhChild' + u, 'Ph' + u,
                                             'ph.child.' + u + '@test.com', '9876543210');

        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},"children":[' +
            '{"firstName":"PhChild' + u + '","lastName":"Ph' + u + '",' +
            '"email":"ph.child.' + u + '@test.com",' +
            '"mobilePhone":"98765-43210"}]}';

        RestResponse res = setupRestContext(payload);

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true, r.get('success'),
                            'Formatted phone should normalize to digits and still match | ' +
                            res.responseBody.toString());
        System.assertEquals('Account Head Relationship created successfully.', r.get('message'));
    }

    @isTest
    static void testPhoneNormalization_ParenthesesAndSpaces_StillMatches() {
        String  u      = uid();
        Account parent = createPersonAccount('Ph2Head' + u, 'Ph2' + u,
                                             'ph2.head.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Ph2Child' + u, 'Ph2' + u,
                                             'ph2.child.' + u + '@test.com', '8001234567');

        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},"children":[' +
            '{"firstName":"Ph2Child' + u + '","lastName":"Ph2' + u + '",' +
            '"email":"ph2.child.' + u + '@test.com",' +
            '"mobilePhone":"(800) 123-4567"}]}';

        RestResponse res = setupRestContext(payload);

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(true, r.get('success'),
                            '"(800) 123-4567" should normalize to "8001234567" and match | ' +
                            res.responseBody.toString());
        System.assertEquals('Account Head Relationship created successfully.', r.get('message'));
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 11 — Phone mismatch gives specific error message
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testEmailFoundButPhoneMismatch_ReturnsPhoneErrorMessage() {
        String  u      = uid();
        Account parent = createPersonAccount('PMHead' + u, 'PM' + u,
                                             'pm.head.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('PMChild' + u, 'PM' + u,
                                             'pm.child.' + u + '@test.com', '1112223333');

        // Correct email, wrong phone
        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"PMChild' + u + '","lastName":"PM' + u + '",' +
            '"email":"pm.child.' + u + '@test.com","mobilePhone":"9999999999"}]}'
        );

        Test.startTest();
        AccountHeadLinkResource.linkAccountHead();
        Test.stopTest();

        System.assertEquals(200, res.statusCode);
        List<Object> results = (List<Object>) parseResponse(res).get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());

        Map<String, Object> r = (Map<String, Object>) results[0];
        System.assertEquals(false, r.get('success'));
        System.assertEquals(
            'Mobile phone number does not match. Please verify the mobile number and try again.',
            r.get('message')
        );
    }
}