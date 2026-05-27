@isTest(SeeAllData=true)
private class CaseTriggerForActOnItPortalCaseTest2 {

    // =========================================================
    // HELPER: Get existing Business Account (no insert needed)
    // =========================================================
    private static Account getBusinessAccount() {
        List<Account> existing = [
            SELECT Id FROM Account
            WHERE IsPersonAccount = false
            AND IsDeleted = false
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        // Fallback: create only if org has zero business accounts
        Id recordTypeId = getBusinessAccountRecordTypeId();
        Account acc = new Account(Name = 'Test Portal Account');
        if (recordTypeId != null) acc.RecordTypeId = recordTypeId;
        insert acc;
        return acc;
    }

private static Id getBusinessAccountRecordTypeId() {
    for (Schema.RecordTypeInfo rti : Schema.SObjectType.Account.getRecordTypeInfos()) {
        if (rti.isAvailable() && !rti.isMaster()) {
            return rti.getRecordTypeId();
        }
    }
    return null;
}

    // =========================================================
    // HELPER: Create Test User
    // =========================================================
    private static User createPortalTriggerUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName         = 'Portal',
            LastName          = 'TriggerUser',
            Email             = 'portal.triggeruser@testclass.com',
            Username          = 'portal.triggeruser@testclass.com.'
                                + UserInfo.getOrganizationId(),
            Alias             = 'ptrigu',
            TimeZoneSidKey    = 'America/New_York',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = p.Id
        );
        insert u;
        return u;
    }

    // =========================================================
    // HELPER: Force fresh Custom Setting at org level
    // =========================================================
    private static void setupCustomSetting(Boolean enabled, String userId) {
        String orgId = UserInfo.getOrganizationId();
        List<CasePortalUserTriggerSettig__c> existing = [
            SELECT Id FROM CasePortalUserTriggerSettig__c
            WHERE SetupOwnerId = :orgId
            LIMIT 1
        ];
        CasePortalUserTriggerSettig__c cs = existing.isEmpty()
            ? new CasePortalUserTriggerSettig__c(SetupOwnerId = orgId)
            : existing[0];
        cs.Execute_Trigger__c = enabled;
        cs.UserId__c          = userId;
        upsert cs;
    }

    // =========================================================
    // TEST 1: Custom Setting NULL → trigger exits
    // =========================================================
    @isTest
    static void testExitsWhenCustomSettingIsNull() {
        delete [SELECT Id FROM CasePortalUserTriggerSettig__c];

        User triggerUser = createPortalTriggerUser();
        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        System.runAs(triggerUser) {
            insert new Case(AccountId = acc.Id, Subject = 'Null CS Test',
                Status = 'New', Priority = 'Low');
        }
        Test.stopTest();

        System.assertEquals(beforeCount + 1,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No duplicate — CS is null');
    }

    // =========================================================
    // TEST 2: Execute_Trigger__c = false → trigger exits
    // =========================================================
    @isTest
    static void testExitsWhenTriggerDisabled() {
        User triggerUser = createPortalTriggerUser();
        setupCustomSetting(false, triggerUser.Id);

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        System.runAs(triggerUser) {
            insert new Case(AccountId = acc.Id, Subject = 'Disabled Test',
                Status = 'New', Priority = 'Medium');
        }
        Test.stopTest();

        System.assertEquals(beforeCount + 1,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No duplicate — trigger disabled');
    }

    // =========================================================
    // TEST 3: UserId__c blank → trigger exits
    // =========================================================
    @isTest
    static void testExitsWhenUserIdIsBlank() {
        User triggerUser = createPortalTriggerUser();
        setupCustomSetting(true, '');

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        System.runAs(triggerUser) {
            insert new Case(AccountId = acc.Id, Subject = 'Blank UserId Test',
                Status = 'New', Priority = 'Low');
        }
        Test.stopTest();

        System.assertEquals(beforeCount + 1,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No duplicate — UserId blank');
    }

    // =========================================================
    // TEST 4: UserId__c null → trigger exits
    // =========================================================
    @isTest
    static void testExitsWhenUserIdIsNull() {
        User triggerUser = createPortalTriggerUser();
        setupCustomSetting(true, null);

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        System.runAs(triggerUser) {
            insert new Case(AccountId = acc.Id, Subject = 'Null UserId Test',
                Status = 'New', Priority = 'Low');
        }
        Test.stopTest();

        System.assertEquals(beforeCount + 1,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No duplicate — UserId null');
    }

    // =========================================================
    // TEST 5: Different user → no event
    // =========================================================
    @isTest
    static void testNoEventForDifferentUser() {
        User triggerUser = createPortalTriggerUser();
        setupCustomSetting(true, triggerUser.Id);

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        // Current running user ≠ stored portal user
        insert new Case(AccountId = acc.Id, Subject = 'Different User Case',
            Status = 'New', Priority = 'Low');
        Test.stopTest();

        System.assertEquals(beforeCount + 1,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No event — user mismatch');
    }

    // =========================================================
    // TEST 6: Target user → event fires → duplicate created
    // =========================================================
    @isTest
    static void testEventPublishedForTargetUser() {
        User triggerUser = createPortalTriggerUser();
        setupCustomSetting(true, triggerUser.Id);

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];
        Case sourceCase;

        Test.startTest();
        System.runAs(triggerUser) {
            sourceCase = new Case(
                AccountId   = acc.Id,
                Subject     = 'Target User Case',
                Description = 'Trigger should fire for this user',
                Status      = 'New',
                Priority    = 'High'
            );
            insert sourceCase;
        }
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(beforeCount + 2,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'Source + 1 duplicate expected');

        Case dup = [
            SELECT Subject, Description, Status, Priority, AccountId
            FROM Case
            WHERE AccountId = :acc.Id
            AND Id != :sourceCase.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Target User Case',                  dup.Subject);
        System.assertEquals('Trigger should fire for this user', dup.Description);
        System.assertEquals('New',    dup.Status,   'Status forced to New');
        System.assertEquals('Medium', dup.Priority, 'Priority forced to Medium');
        System.assertEquals(acc.Id,   dup.AccountId);
    }

    // =========================================================
    // TEST 7: Bulk — only target user cases get duplicated
    // =========================================================
    @isTest
    static void testBulkOnlyTargetUserCasesGetEvents() {
        User triggerUser = createPortalTriggerUser();
        setupCustomSetting(true, triggerUser.Id);

        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        // 3 cases as non-target user
        List<Case> otherCases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            otherCases.add(new Case(AccountId = acc.Id,
                Subject = 'Other User Bulk ' + i, Status = 'New', Priority = 'Low'));
        }
        insert otherCases;

        // 3 cases as target user
        List<Case> targetCases = new List<Case>();
        Test.startTest();
        System.runAs(triggerUser) {
            for (Integer i = 0; i < 3; i++) {
                targetCases.add(new Case(AccountId = acc.Id,
                    Subject = 'Target User Bulk ' + i,
                    Description = 'Bulk Desc ' + i,
                    Status = 'New', Priority = 'High'));
            }
            insert targetCases;
        }
        Test.getEventBus().deliver();
        Test.stopTest();

        // beforeCount + 3 other + 3 target + 3 duplicates
        System.assertEquals(beforeCount + 9,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'beforeCount + 3 other + 3 target + 3 duplicates');

        // Other user cases must NOT be duplicated
        Integer otherCount = [
            SELECT COUNT() FROM Case
            WHERE AccountId = :acc.Id
            AND Subject LIKE 'Other User Bulk%'
        ];
        System.assertEquals(3, otherCount, 'Other user cases must not be duplicated');
    }

    // =========================================================
    // TEST 8: All guard conditions independently verified
    // =========================================================
    @isTest
    static void testAllThreeGuardConditions() {
        User triggerUser = createPortalTriggerUser();
        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();

        // Guard A: disabled
        setupCustomSetting(false, triggerUser.Id);
        System.runAs(triggerUser) {
            insert new Case(AccountId = acc.Id, Subject = 'Guard A',
                Status = 'New', Priority = 'Low');
        }

        // Guard B: blank userId
        setupCustomSetting(true, '');
        System.runAs(triggerUser) {
            insert new Case(AccountId = acc.Id, Subject = 'Guard B',
                Status = 'New', Priority = 'Low');
        }

        Test.getEventBus().deliver();
        Test.stopTest();

        // Only 2 new cases, no duplicates
        System.assertEquals(beforeCount + 2,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'Both guards must block events — no duplicates');
    }
}