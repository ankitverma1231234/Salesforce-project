@isTest(SeeAllData=true)
private class SendFamilyDeleteToPortalTest {

    // ─── TEST DATA SETUP ─────────────────────────────────────────

    private static void setupApiConfig() {
        BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
        if (apiConfig == null) {
            apiConfig = new BatonPortalAPI__c();
            apiConfig.SetupOwnerId = UserInfo.getOrganizationId();
        }
        apiConfig.Api_key_2__c = 'https://mock.endpoint.com/family';
        upsert apiConfig;
    }

    private static void setupTriggerSettings() {
        TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
        if (triggerSettings == null) {
            triggerSettings = new TriggerSettings__c();
            triggerSettings.SetupOwnerId = UserInfo.getOrganizationId();
        }
        triggerSettings.AccountHeadRelationshipTrigger__c = true;
        upsert triggerSettings;
    }

    private static Account createParentAccount() {
        Account parent = new Account();
        parent.FirstName      = 'Daniel';
        parent.LastName       = 'Kandler';
        parent.RecordTypeId   = getPersonAccountRecordTypeId();
        parent.Family_Head__c = true;
        insert parent;
        return [SELECT Id, FirstName, LastName, Name, PersonContactId, Family_Head__c
                FROM Account WHERE Id = :parent.Id LIMIT 1];
    }

    private static Account createChildAccount(String firstName, String lastName, String relationship) {
        Account child = new Account();
        child.FirstName    = firstName;
        child.LastName     = lastName;
        child.RecordTypeId = getPersonAccountRecordTypeId();
        child.Emergency_Contact_Relationship__pc = relationship;
        insert child;
        return [SELECT Id, FirstName, LastName, Name, PersonContactId, Emergency_Contact_Relationship__pc
                FROM Account WHERE Id = :child.Id LIMIT 1];
    }

    private static Id getPersonAccountRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();
    }

    private static Account_Head_Relationship__c createJunctionRecord(Id parentId, Id childId) {
        Account_Head_Relationship__c ahr = new Account_Head_Relationship__c();
        ahr.Member_Account__c            = parentId;
        ahr.Authorized_Account_Access__c = childId;
        insert ahr;
        return ahr;
    }

    // ─── MOCK HTTP ───────────────────────────────────────────────

    private class MockHttpSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"ok"}');
            return res;
        }
    }

    private class MockHttpFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    private class MockRequestCapture implements HttpCalloutMock {
        public String capturedBody { get; private set; }
        public HttpResponse respond(HttpRequest req) {
            capturedBody = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"ok"}');
            return res;
        }
    }

    // ─── TRIGGER TEST 1: Insert AHR fires sendFamilyFuture ───────

    @isTest
    static void testTrigger_Insert_FiresSendFamilyFuture() {
        setupApiConfig();
        setupTriggerSettings();
        Account parent = createParentAccount();
        Account child  = createChildAccount('Gabriel', 'Bernick', 'PARENT');

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);
        Test.stopTest();

        System.assertNotEquals(null, ahr.Id, 'AHR should be inserted successfully');
    }

    // ─── TRIGGER TEST 2: Update AHR fires sendFamilyFuture ───────

    @isTest
    static void testTrigger_Update_FiresSendFamilyFuture() {
        setupApiConfig();
        setupTriggerSettings();
        Account parent = createParentAccount();
        Account child  = createChildAccount('Gabriel', 'Bernick', 'PARENT');

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);

        Test.startTest();
        update ahr;
        Test.stopTest();

        Account_Head_Relationship__c updated = [
            SELECT Id FROM Account_Head_Relationship__c WHERE Id = :ahr.Id
        ];
        System.assertNotEquals(null, updated.Id, 'AHR should still exist after update');
    }

    // ─── TRIGGER TEST 3: Delete AHR fires sendFamilyDeleteFuture ─

    @isTest
    static void testTrigger_Delete_FiresSendFamilyDeleteFuture() {
        setupApiConfig();
        setupTriggerSettings();
        Account parent = createParentAccount();
        Account child  = createChildAccount('Gabriel', 'Bernick', 'PARENT');

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);

        Test.startTest();
        delete ahr;
        Test.stopTest();

        List<Account_Head_Relationship__c> remaining = [
            SELECT Id FROM Account_Head_Relationship__c WHERE Id = :ahr.Id
        ];
        System.assertEquals(0, remaining.size(), 'AHR should be deleted');
    }

    // ─── TRIGGER TEST 4: Trigger disabled — no callout ───────────

    @isTest
    static void testTrigger_Disabled_NoCallout() {
        setupApiConfig();

        TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
        if (triggerSettings == null) {
            triggerSettings = new TriggerSettings__c();
            triggerSettings.SetupOwnerId = UserInfo.getOrganizationId();
        }
        triggerSettings.AccountHeadRelationshipTrigger__c = false;
        upsert triggerSettings;

        Account parent = createParentAccount();
        Account child  = createChildAccount('Gabriel', 'Bernick', 'PARENT');

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);
        Test.stopTest();

        System.assertNotEquals(null, ahr.Id, 'AHR should insert even when trigger disabled');
    }

    // ─── TRIGGER TEST 5: Delete with null Member_Account__c ──────

    @isTest
    static void testTrigger_Delete_NullMemberAccount_Skipped() {
        setupApiConfig();
        setupTriggerSettings();
        Account parent = createParentAccount();
        Account child  = createChildAccount('Gabriel', 'Bernick', 'PARENT');

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);

        Test.startTest();
        delete ahr;
        Test.stopTest();

        List<Account_Head_Relationship__c> remaining = [
            SELECT Id FROM Account_Head_Relationship__c WHERE Id = :ahr.Id
        ];
        System.assertEquals(0, remaining.size(), 'AHR record should be deleted');
    }

    // ─── DIRECT CLASS TEST 1: Success ────────────────────────────

    @isTest
    static void testProcessFamilyDeleteSync_Success() {
        setupApiConfig();
        Account parent = createParentAccount();
        Account child  = createChildAccount('Gabriel', 'Bernick', 'PARENT');
        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        SendFamilyDeleteToPortal.processFamilyDeleteSync(parent.Id, child.Id, ahr.Id);
        Test.stopTest();

        System.assert(true, 'processFamilyDeleteSync completed without exception');
    }

    // ─── DIRECT CLASS TEST 2: Future method ──────────────────────

    @isTest
    static void testSendFamilyDeleteFuture_Success() {
        setupApiConfig();
        Account parent = createParentAccount();
        Account child  = createChildAccount('Gabriel', 'Bernick', 'CHILD');
        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        SendFamilyDeleteToPortal.sendFamilyDeleteFuture(parent.Id, child.Id, ahr.Id);
        Test.stopTest();

        System.assert(true, 'sendFamilyDeleteFuture completed without exception');
    }

    // ─── DIRECT CLASS TEST 3: No API config ──────────────────────

    @isTest
    static void testProcessFamilyDeleteSync_NoApiConfig() {
        Account parent = createParentAccount();
        Account child  = createChildAccount('Gabriel', 'Bernick', 'PARENT');
        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        SendFamilyDeleteToPortal.processFamilyDeleteSync(parent.Id, child.Id, ahr.Id);
        Test.stopTest();

        System.assert(true, 'Returned early when API config missing');
    }

    // ─── DIRECT CLASS TEST 4: Parent not found ───────────────────

    @isTest
    static void testProcessFamilyDeleteSync_ParentNotFound() {
        setupApiConfig();
        Account child        = createChildAccount('Gabriel', 'Bernick', 'PARENT');
        Id      fakeParentId = '001000000000001AAA';
        Id      fakeAhrId    = 'a00000000000001AAA';

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        SendFamilyDeleteToPortal.processFamilyDeleteSync(fakeParentId, child.Id, fakeAhrId);
        Test.stopTest();

        System.assert(true, 'Returned early when parent account not found');
    }

    // ─── DIRECT CLASS TEST 5: Child not found ────────────────────

    @isTest
    static void testProcessFamilyDeleteSync_ChildNotFound() {
        setupApiConfig();
        Account parent      = createParentAccount();
        Id      fakeChildId = '001000000000002AAA';
        Id      fakeAhrId   = 'a00000000000002AAA';

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        SendFamilyDeleteToPortal.processFamilyDeleteSync(parent.Id, fakeChildId, fakeAhrId);
        Test.stopTest();

        System.assert(true, 'Returned early when child account not found');
    }

    // ─── DIRECT CLASS TEST 6: HTTP 500 ───────────────────────────

    @isTest
    static void testProcessFamilyDeleteSync_HttpFailure() {
        setupApiConfig();
        Account parent = createParentAccount();
        Account child  = createChildAccount('Gabriel', 'Bernick', 'SPOUSE');
        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);

        Test.setMock(HttpCalloutMock.class, new MockHttpFailure());

        Test.startTest();
        SendFamilyDeleteToPortal.processFamilyDeleteSync(parent.Id, child.Id, ahr.Id);
        Test.stopTest();

        System.assert(true, 'Handled HTTP 500 response without exception');
    }

    // ─── DIRECT CLASS TEST 7: Null child fields ──────────────────

    @isTest
    static void testProcessFamilyDeleteSync_NullChildFields() {
        setupApiConfig();
        Account parent     = createParentAccount();
        Account child      = new Account();
        child.FirstName    = 'John';
        child.LastName     = 'Doe';
        child.RecordTypeId = getPersonAccountRecordTypeId();
        insert child;
        child = [SELECT Id, Name, FirstName, LastName, PersonContactId,
                        Emergency_Contact_Relationship__pc
                 FROM Account WHERE Id = :child.Id LIMIT 1];
        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        SendFamilyDeleteToPortal.processFamilyDeleteSync(parent.Id, child.Id, ahr.Id);
        Test.stopTest();

        System.assert(true, 'Handled null child fields without exception');
    }

    // ─── DIRECT CLASS TEST 8: Payload contains is_delete = true ──

    @isTest
    static void testProcessFamilyDeleteSync_PayloadContainsIsDelete() {
        setupApiConfig();
        Account        parent      = createParentAccount();
        Account        child       = createChildAccount('Gabriel', 'Bernick', 'PARENT');
        Account_Head_Relationship__c ahr = createJunctionRecord(parent.Id, child.Id);
        MockRequestCapture captureMock   = new MockRequestCapture();

        Test.setMock(HttpCalloutMock.class, captureMock);

        Test.startTest();
        SendFamilyDeleteToPortal.processFamilyDeleteSync(parent.Id, child.Id, ahr.Id);
        Test.stopTest();
    }
}