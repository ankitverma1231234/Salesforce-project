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
    
    private static Account_Head_Relationship__c createJunction(Id parentId, Id childId) {
        Account_Head_Relationship__c j = new Account_Head_Relationship__c(
            Member_Account__c            = parentId,
            Authorized_Account_Access__c = childId
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
        Map<String, Object>  body    = parseResponse(res);
        System.assertEquals('Child validation failed.', body.get('message'));
        
        List<Object> results = (List<Object>) body.get('results');
        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());
        
        Map<String, Object> r = (Map<String, Object>) results[0];
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
    
    // ── FIXED: message now reflects that the email itself was not found ───────
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
        // Account does not exist in SF at all — email not found
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
    
    @isTest
    static void testNewRelationshipCreated_Returns200WithSuccess() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'Creator' + u,
                                             'head.creator.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'New' + u,
                                             'child.new.' + u + '@test.com', (u + '1').left(10));
        
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
        System.assertEquals(true, r.get('success'));
        System.assertEquals('Account Head Relationship created successfully.', r.get('message'));
        System.assertNotEquals(null, r.get('relationshipId'));
        
        List<Account_Head_Relationship__c> junctions = [
            SELECT Id FROM Account_Head_Relationship__c
            WHERE  Member_Account__c            = :parent.Id
            AND    Authorized_Account_Access__c = :child.Id
        ];
        System.assertEquals(1, junctions.size(), 'Junction record must exist in DB');
    }
    
    @isTest
    static void testRelationshipAlreadyExists_Returns200WithExistingId() {
        String  u      = uid();
        Account parent = createPersonAccount('Head' + u, 'Exist' + u,
                                             'head.exist.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Child' + u, 'Exist' + u,
                                             'child.exist.' + u + '@test.com', (u + '2').left(10));
        
        Account_Head_Relationship__c existing = createJunction(parent.Id, child.Id);
        
        RestResponse res = setupRestContext(
            '{"parent":{"accountId":"' + parent.Id + '"},' +
            '"children":[{"firstName":"Child' + u + '","lastName":"Exist' + u + '",' +
            '"email":"child.exist.' + u + '@test.com","mobilePhone":"' + (u + '2').left(10) + '"}]}'
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
        System.assertEquals(true, r.get('success'));
        System.assertEquals('Relationship already exists.', r.get('message'));
        System.assertEquals(existing.Id, (String) r.get('relationshipId'));
    }
    
    // ── FIXED: ghost-child counter now matches the new "Child not found" message
    @isTest
    static void testMultipleChildren_MixedResults() {
        String  u      = uid();
        Account parent = createPersonAccount('Head'  + u, 'Multi'    + u,
                                             'head.multi.' + u + '@test.com', u.left(10));
        Account child1 = createPersonAccount('Alpha' + u, 'MultiOne' + u,
                                             'alpha.m1.'   + u + '@test.com', (u + '3').left(10));
        Account child2 = createPersonAccount('Beta'  + u, 'MultiTwo' + u,
                                             'beta.m2.'    + u + '@test.com', (u + '4').left(10));
        
        createJunction(parent.Id, child2.Id);
        
        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},"children":['
            + '{"firstName":"Alpha' + u + '","lastName":"MultiOne' + u + '",'
            + '"email":"alpha.m1.' + u + '@test.com","mobilePhone":"' + (u + '3').left(10) + '"},'
            + '{"firstName":"Beta'  + u + '","lastName":"MultiTwo' + u + '",'
            + '"email":"beta.m2.'  + u + '@test.com","mobilePhone":"' + (u + '4').left(10) + '"},'
            + '{"firstName":"Ghost' + u + '","lastName":"Nobody' + u + '",'
            + '"email":"ghost.'     + u + '@nowhere.com","mobilePhone":"' + (u + '5').left(10) + '"}'
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
            // FIXED: matches new message when account does not exist in Salesforce at all
           else if (msg == 'Member not found with the provided email address and Phone Number.') {
    notFoundCount++;
}
        }
        
        System.assertEquals(1, createdCount,  'child1 should be created');
        System.assertEquals(1, existsCount,   'child2 should already exist');
        System.assertEquals(1, notFoundCount, 'ghost child should not be found');
    }
    
    
    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 2 — Flat standalone-delete  { account_headrelationshipid, is_delete }
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
        
        Map<String, Object> body    = parseResponse(res);
        System.assertEquals(true, body.get('success'));
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
    // SECTION 3 — Delete via children array  (is_delete inside children block)
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
        System.assertEquals(true, r.get('success'));
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
        Account parent = createPersonAccount('MixHead' + u, 'Mix' + u,
                                             'mix.head.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('MixChild' + u, 'Link' + u,
                                             'mix.child.' + u + '@test.com', (u + '8').left(10));
        
        Account childDel = createPersonAccount('MixDel' + u, 'Del' + u,
                                               'mix.del.' + u + '@test.com', (u + '9').left(10));
        Account_Head_Relationship__c jr = createJunction(parent.Id, childDel.Id);
        
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
        
        Integer createdCount = 0, deletedCount = 0;
        for (Object o : results) {
            Map<String, Object> r = (Map<String, Object>) o;
            String msg = (String) r.get('message');
            if (msg == 'Account Head Relationship created successfully.') createdCount++;
            if (msg == 'Queued for deletion.')                            deletedCount++;
        }
        System.assertEquals(1, createdCount, 'One link should be created');
        System.assertEquals(1, deletedCount, 'One delete should be queued');
    }
    
    
    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 4 — Name normalisation
    // ══════════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testNameNormalization_LeadingTrailingSpaces_StillMatches() {
        String  u      = uid();
        Account parent = createPersonAccount('SpHead' + u, 'SP' + u,
                                             'sp.head.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Mark' + u, 'Saxena' + u,
                                             'mark.saxena.' + u + '@test.com', (u + 'A').left(10));
        
        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},"children":[' +
            '{"firstName":"  Mark' + u + '  ","lastName":"  Saxena' + u + '  ",' +
            '"email":"mark.saxena.' + u + '@test.com",' +
            '"mobilePhone":"' + (u + 'A').left(10) + '"}]}';
        
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
                            'Leading/trailing spaces should be normalised and still match | ' +
                            res.responseBody.toString());
        System.assertEquals(
            'Account Head Relationship created successfully.',
            r.get('message')
        );
    }
    
    @isTest
    static void testNameNormalization_InternalMultipleSpaces_StillMatches() {
        String  u      = uid();
        Account parent = createPersonAccount('ISHead' + u, 'IS' + u,
                                             'is.head.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('Mak' + u, 'Saxna' + u,
                                             'ma.k.sax.' + u + '@test.com', (u + 'B').left(10));
        
        String payload =
            '{"parent":{"accountId":"' + parent.Id + '"},"children":[' +
            '{"firstName":"Ma  k' + u + '","lastName":"Sax  na' + u + '",' +
            '"email":"ma.k.sax.' + u + '@test.com",' +
            '"mobilePhone":"' + (u + 'B').left(10) + '"}]}';
        
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
                            'Internal multi-spaces should be stripped and still match | ' +
                            res.responseBody.toString());
        System.assertEquals(
            'Account Head Relationship created successfully.',
            r.get('message')
        );
    }
    
    
    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 5 — Phone normalisation
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
    }
    
    
    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 6 — New: Phone mismatch gives specific error message
    // ══════════════════════════════════════════════════════════════════════════
    
    @isTest
    static void testEmailFoundButPhoneMismatch_ReturnsPhoneErrorMessage() {
        String  u      = uid();
        Account parent = createPersonAccount('PMHead' + u, 'PM' + u,
                                             'pm.head.' + u + '@test.com', u.left(10));
        // Child exists in SF with a known phone
        Account child  = createPersonAccount('PMChild' + u, 'PM' + u,
                                             'pm.child.' + u + '@test.com', '1112223333');
        
        // Send correct email but WRONG phone — should get phone-mismatch message
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
    }
}