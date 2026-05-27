@isTest(SeeAllData=true)
private class CaseTriggerForActOnItNotificationTest {

    // ─── Helper: Get or Create Business Account ──────────────────────────
    private static Account getBusinessAccount() {
        List<Account> existing = [
            SELECT Id FROM Account
            WHERE IsPersonAccount = false
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        Id businessRT = getBusinessAccountRecordTypeId();
        Account ba = new Account(Name = 'Test Business Account');
        if (businessRT != null) ba.RecordTypeId = businessRT;
        insert ba;
        return ba;
    }

    private static Id getBusinessAccountRecordTypeId() {
        List<String> possibleRTNames = new List<String>{
            'Business_Account', 'IndustriesBusinessAccount',
            'Business', 'Organization', 'Household'
        };
        Map<String, Schema.RecordTypeInfo> rtMap =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        for (String rtName : possibleRTNames) {
            if (rtMap.containsKey(rtName)) return rtMap.get(rtName).getRecordTypeId();
        }
        return null;
    }

    // ─── Helper: Get or Create Test User ────────────────────────────────
    private static User getOrCreateTestUser() {
        List<User> existing = [
            SELECT Id FROM User
            WHERE Email = 'portal.actonit@testorg.com'
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName         = 'Portal',
            LastName          = 'ActOnIt',
            Email             = 'portal.actonit@testorg.com',
            Username          = 'portal.actonit@testorg.com.' + UserInfo.getOrganizationId(),
            Alias             = 'pacton',
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = p.Id
        );
        insert u;
        return u;
    }

    // ─── Helper: Setup Custom Setting ───────────────────────────────────
    private static User setupCustomSettingWithUser() {
        User testUser = getOrCreateTestUser();

        CasePortalUserTriggerSettig__c cs = CasePortalUserTriggerSettig__c.getInstance();
        if (cs == null) cs = new CasePortalUserTriggerSettig__c();
        cs.Execute_Trigger__c = true;
        cs.UserId__c          = testUser.Id;
        upsert cs;

        return testUser;
    }

    // =========================================================
    // TEST 1: Trigger disabled → no events fired
    // =========================================================
    @isTest
    static void testTriggerDisabled() {
        User testUser = setupCustomSettingWithUser();

        // Now disable
        CasePortalUserTriggerSettig__c cs = CasePortalUserTriggerSettig__c.getInstance();
        cs.Execute_Trigger__c = false;
        upsert cs;

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        System.runAs(testUser) {
            insert new Case(AccountId = acc.Id, Subject = 'Disabled Test', Status = 'New', Priority = 'Medium');
        }
        Test.stopTest();

        System.assertEquals(beforeCount + 1, [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No duplicate when trigger is disabled');
    }

    // =========================================================
    // TEST 2: UserId__c blank → trigger exits safely
    // =========================================================
    @isTest
    static void testBlankUserIdExitsSafely() {
        User testUser = setupCustomSettingWithUser();

        CasePortalUserTriggerSettig__c cs = CasePortalUserTriggerSettig__c.getInstance();
        cs.UserId__c = '';
        upsert cs;

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        System.runAs(testUser) {
            insert new Case(AccountId = acc.Id, Subject = 'Blank UserId Test', Status = 'New', Priority = 'Low');
        }
        Test.stopTest();

        System.assertEquals(beforeCount + 1, [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No duplicate when UserId__c is blank');
    }

    // =========================================================
    // TEST 3: Null custom setting → trigger exits safely
    // =========================================================
    @isTest
    static void testNullCustomSettingExitsSafely() {
        CasePortalUserTriggerSettig__c cs = CasePortalUserTriggerSettig__c.getInstance();
        if (cs != null && cs.Id != null) delete cs;

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        insert new Case(AccountId = acc.Id, Subject = 'Null CS Test', Status = 'New', Priority = 'Low');
        Test.stopTest();

        System.assertEquals(beforeCount + 1, [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'Trigger exits safely when custom setting is null');
    }

    // =========================================================
    // TEST 4: Case created by target user → event fires → queueable runs
    // =========================================================
 

    // =========================================================
    // TEST 5: Different user → no event fires
    // =========================================================
    @isTest
    static void testTriggerDoesNotFireForOtherUser() {
        setupCustomSettingWithUser(); // ensure custom setting is active

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        insert new Case(AccountId = acc.Id, Subject = 'Other User Case', Status = 'New', Priority = 'Low');
        Test.stopTest();

        System.assertEquals(beforeCount + 1, [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No duplicate for a different user');
    }

    // =========================================================
    // TEST 6: Platform Event subscriber enqueues job
    // =========================================================
    @isTest
    static void testPlatformEventSubscriberEnqueuesJob() {
        setupCustomSettingWithUser();
        Account acc = getBusinessAccount();

        Case sourceCase = new Case(
            AccountId = acc.Id, Subject = 'Event Subscriber Test',
            Description = 'Testing subscriber', Status = 'New', Priority = 'Low'
        );
        insert sourceCase;

        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        Database.SaveResult sr = EventBus.publish(
            new Case_Auto_Create_Event__e(Source_Case_Id__c = sourceCase.Id)
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert(sr.isSuccess(), 'Platform event should publish successfully');
        System.assertEquals(beforeCount + 1, [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'Queueable should create 1 duplicate');
    }

    // =========================================================
    // TEST 7: Queueable with empty set → no DML
    // =========================================================
    @isTest
    static void testQueueableWithEmptySet() {
        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        System.enqueueJob(new CaseAutoCreateQueueablePortalUserActOnIt(new Set<Id>()));
        Test.stopTest();

        System.assertEquals(beforeCount, [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No cases created for empty input');
    }

    // =========================================================
    // TEST 8: Queueable bulk — 5 cases → 5 duplicates
    // =========================================================
    @isTest
    static void testQueueableBulk() {
        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        List<Case> sourceCases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            sourceCases.add(new Case(
                AccountId = acc.Id, Subject = 'Bulk Case ' + i,
                Description = 'Bulk Desc ' + i, Status = 'New', Priority = 'High'
            ));
        }
        insert sourceCases;
        Set<Id> ids = new Map<Id, Case>(sourceCases).keySet();

        Test.startTest();
        System.enqueueJob(new CaseAutoCreateQueueablePortalUserActOnIt(ids));
        Test.stopTest();

        System.assertEquals(beforeCount + 10, [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            '5 source + 5 duplicates expected');

        for (Case dup : [SELECT Status, Priority FROM Case WHERE AccountId = :acc.Id AND Id NOT IN :ids]) {
            System.assertEquals('New',    dup.Status,   'Forced Status = New');
            System.assertEquals('Medium', dup.Priority, 'Forced Priority = Medium');
        }
    }
}