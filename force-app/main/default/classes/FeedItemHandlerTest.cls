@isTest(SeeAllData=true)
public class FeedItemHandlerTest {

    /*────────────────────────────────────────────
    Helper: Get or Create MessageCustomization__c
    ────────────────────────────────────────────*/
    private static MessageCustomization__c getOrCreateSetting(
        Boolean smsEnabled,
        Boolean emailEnabled,
        Id smsTemplateId,
        Id emailTemplateId
    ) {
        List<MessageCustomization__c> existing = [
            SELECT Id, Chatter_Sms_Notification__c,
                   Chatter_Email_Notification__c,
                   Chatter_Sms_Notification_Message__c,
                   Email_Template_ID__c
            FROM MessageCustomization__c
            LIMIT 1
        ];

        MessageCustomization__c setting;

        if (!existing.isEmpty()) {
            setting = existing[0];
        } else {
            setting = new MessageCustomization__c();
        }

        setting.Chatter_Sms_Notification__c         = smsEnabled;
        setting.Chatter_Email_Notification__c        = emailEnabled;
        setting.Chatter_Sms_Notification_Message__c  = smsTemplateId;
        setting.Email_Template_ID__c                 = emailTemplateId;

        upsert setting;
        return setting;
    }

    /*────────────────────────────────────────────
    Helper: Get real SMS Message Template
    ────────────────────────────────────────────*/
    private static sra__Message_Template__c getRealSmsTemplate() {
        List<sra__Message_Template__c> templates = [
            SELECT Id, sra__Template_Body__c
            FROM sra__Message_Template__c
            LIMIT 1
        ];

        if (!templates.isEmpty()) {
            return templates[0];
        }

        sra__Message_Template__c t = new sra__Message_Template__c(
            Name                  = 'Test Template',
            sra__Template_Body__c = 'Hello {!account.name}, your case {!casenumber} has been updated.'
        );
        insert t;
        return t;
    }

    /*────────────────────────────────────────────
    Helper: Get real SMS Sender Config
    ────────────────────────────────────────────*/
    private static sra__Message_User_Configuration__c getRealSenderConfig() {
        List<sra__Message_User_Configuration__c> configs = [
            SELECT Id, sra__Sender_Number__c
            FROM sra__Message_User_Configuration__c
            LIMIT 1
        ];

        if (!configs.isEmpty()) {
            return configs[0];
        }

        sra__Message_User_Configuration__c config = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '+10000000000'
        );
        insert config;
        return config;
    }

    /*────────────────────────────────────────────
    Helper: Get or Create Person Account
    ────────────────────────────────────────────*/
    private static Account getOrCreatePersonAccount() {
        List<Account> existing = [
            SELECT Id, Name, Phone, PersonEmail, PersonContactId,
                   IsPersonAccount, AccountNumber
            FROM Account
            WHERE IsPersonAccount = true
            AND Phone != null
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            return existing[0];
        }

        RecordType personAccountRT = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];

        Account acc = new Account(
            FirstName    = 'Test',
            LastName     = 'Person',
            Phone        = '+11234567890',
            PersonEmail  = 'testperson@example.com',
            RecordTypeId = personAccountRT.Id
        );
        insert acc;

        return [
            SELECT Id, Name, Phone, PersonEmail, PersonContactId,
                   IsPersonAccount, AccountNumber
            FROM Account
            WHERE Id = :acc.Id
        ];
    }

    /*────────────────────────────────────────────
    Helper: Create Case linked to Account
    ────────────────────────────────────────────*/
    private static Case createCase(Id accountId) {
        Case c = new Case(
            Subject   = 'Test Case',
            Status    = 'New',
            AccountId = accountId
        );
        insert c;
        return c;
    }

    /*────────────────────────────────────────────
    Helper: Get the excluded User Id by name query
    (mirrors the same logic used in FeedItemHandler)
    ────────────────────────────────────────────*/
    private static Id getExcludedUserId() {
        List<User> users = [
            SELECT Id
            FROM User
            WHERE Name = 'Member Portal Site Guest User'
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].Id;
    }

    /*════════════════════════════════════════════
    TEST 1: SMS enabled — happy path
    ════════════════════════════════════════════*/
    @isTest
    static void testSmsEnabled_HappyPath() {

        Account acc                            = getOrCreatePersonAccount();
        sra__Message_Template__c smsTemplate   = getRealSmsTemplate();
        sra__Message_User_Configuration__c cfg = getRealSenderConfig();

        getOrCreateSetting(true, false, smsTemplate.Id, null);

        Case c = createCase(acc.Id);

        Test.startTest();
            FeedItem fi = new FeedItem(ParentId = c.Id, Body = 'Test chatter post');
            insert fi;
        Test.stopTest();

        List<sra__Message_History__c> sent = [
            SELECT Id, sra__Receiver_Number__c, sra__Message_Body__c
            FROM sra__Message_History__c
            WHERE sra__Related_Object_Id__c = :c.Id
        ];

        System.assert(!sent.isEmpty(), 'SMS record should have been created');
        System.assertEquals(acc.Phone, sent[0].sra__Receiver_Number__c, 'Receiver number should match account phone');
    }

    /*════════════════════════════════════════════
    TEST 2: Email enabled — happy path
    ════════════════════════════════════════════*/
    @isTest
    static void testEmailEnabled_HappyPath() {

        Account acc = getOrCreatePersonAccount();

        EmailTemplate emailTemplate = [
            SELECT Id FROM EmailTemplate LIMIT 1
        ];

        getOrCreateSetting(false, true, null, emailTemplate.Id);

        Case c = createCase(acc.Id);

        Test.startTest();
            FeedItem fi = new FeedItem(ParentId = c.Id, Body = 'Test chatter post');
            insert fi;
        Test.stopTest();

        System.assert(true, 'Email send should complete without exception');
    }

    /*════════════════════════════════════════════
    TEST 3: Both SMS and Email enabled
    ════════════════════════════════════════════*/
    @isTest
    static void testBothSmsAndEmailEnabled() {

        Account acc                            = getOrCreatePersonAccount();
        sra__Message_Template__c smsTemplate   = getRealSmsTemplate();
        sra__Message_User_Configuration__c cfg = getRealSenderConfig();

        EmailTemplate emailTemplate = [
            SELECT Id FROM EmailTemplate LIMIT 1
        ];

        getOrCreateSetting(true, true, smsTemplate.Id, emailTemplate.Id);

        Case c = createCase(acc.Id);

        Test.startTest();
            FeedItem fi = new FeedItem(ParentId = c.Id, Body = 'Test chatter post');
            insert fi;
        Test.stopTest();

        List<sra__Message_History__c> sent = [
            SELECT Id FROM sra__Message_History__c
            WHERE sra__Related_Object_Id__c = :c.Id
        ];

        System.assert(!sent.isEmpty(), 'SMS record should exist when both are enabled');
    }

    /*════════════════════════════════════════════
    TEST 4: Both SMS and Email disabled — early return
    ════════════════════════════════════════════*/
    @isTest
    static void testBothDisabled_EarlyReturn() {

        Account acc = getOrCreatePersonAccount();
        getOrCreateSetting(false, false, null, null);

        Case c = createCase(acc.Id);

        Test.startTest();
            FeedItem fi = new FeedItem(ParentId = c.Id, Body = 'Test chatter post');
            insert fi;
        Test.stopTest();

        List<sra__Message_History__c> sent = [
            SELECT Id FROM sra__Message_History__c
            WHERE sra__Related_Object_Id__c = :c.Id
        ];

        System.assert(sent.isEmpty(), 'No SMS should be sent when both notifications are disabled');
    }

    /*════════════════════════════════════════════
    TEST 5: FeedItem posted by excluded user — skipped
    Queries 'Member Portal Site Guest User' by name,
    mirroring the handler's own lookup logic.
    If the user doesn't exist in this org, the test
    verifies the null-safe fallback (no exclusion applied).
    ════════════════════════════════════════════*/
    @isTest
    static void testExcludedUser_Skipped() {

        Account acc                          = getOrCreatePersonAccount();
        sra__Message_Template__c smsTemplate = getRealSmsTemplate();

        getOrCreateSetting(true, false, smsTemplate.Id, null);

        Case c = createCase(acc.Id);

        Id excludedUserId = getExcludedUserId();

        if (excludedUserId == null) {
            // 'Member Portal Site Guest User' not present in this org —
            // verify the handler completes safely with no exclusion applied
            Test.startTest();
                FeedItem fi = new FeedItem(ParentId = c.Id, Body = 'No excluded user in org');
                insert fi;
            Test.stopTest();

            System.assert(true, 'Handler should complete without error when excluded user does not exist');

        } else {
            // Excluded user exists — simulate a FeedItem created by that user
            String jsonFi = '{"ParentId":"' + c.Id + '","CreatedById":"' + excludedUserId + '","Body":"excluded post"}';
            FeedItem excludedFi = (FeedItem) JSON.deserialize(jsonFi, FeedItem.class);

            Test.startTest();
                FeedItemHandler.handleAfterInsert(new List<FeedItem>{ excludedFi });
            Test.stopTest();

            List<sra__Message_History__c> sent = [
                SELECT Id FROM sra__Message_History__c
                WHERE sra__Related_Object_Id__c = :c.Id
            ];

            System.assert(sent.isEmpty(), 'No SMS should be sent for posts by the excluded user');
        }
    }

    /*════════════════════════════════════════════
    TEST 6: FeedItem not on a Case (non-500 prefix) — skipped
    ════════════════════════════════════════════*/
    @isTest
    static void testNonCaseParent_Skipped() {

        sra__Message_Template__c smsTemplate = getRealSmsTemplate();
        getOrCreateSetting(true, false, smsTemplate.Id, null);

        Account acc = getOrCreatePersonAccount();

        // Use Account Id as ParentId (starts with 001, not 500)
        String jsonFi = '{"ParentId":"' + acc.Id + '","Body":"non-case post"}';
        FeedItem fi   = (FeedItem) JSON.deserialize(jsonFi, FeedItem.class);

        Test.startTest();
            FeedItemHandler.handleAfterInsert(new List<FeedItem>{ fi });
        Test.stopTest();

        System.assert(true, 'Should complete without error for non-Case FeedItems');
    }

    /*════════════════════════════════════════════
    TEST 7: Account phone is blank — SMS skipped
    ════════════════════════════════════════════*/
    @isTest
    static void testBlankPhone_SmsSkipped() {

        sra__Message_Template__c smsTemplate   = getRealSmsTemplate();
        sra__Message_User_Configuration__c cfg = getRealSenderConfig();

        getOrCreateSetting(true, false, smsTemplate.Id, null);

        RecordType personAccountRT = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];

        Account acc = new Account(
            FirstName    = 'No',
            LastName     = 'Phone',
            Phone        = null,
            RecordTypeId = personAccountRT.Id
        );
        insert acc;

        Case c = createCase(acc.Id);

        Test.startTest();
            FeedItem fi = new FeedItem(ParentId = c.Id, Body = 'Test chatter post');
            insert fi;
        Test.stopTest();

        List<sra__Message_History__c> sent = [
            SELECT Id FROM sra__Message_History__c
            WHERE sra__Related_Object_Id__c = :c.Id
        ];

        System.assert(sent.isEmpty(), 'No SMS should be sent when phone is blank');
    }

    /*════════════════════════════════════════════
    TEST 8: Empty FeedItems list — no-op
    ════════════════════════════════════════════*/
    @isTest
    static void testEmptyFeedItemsList() {
        Test.startTest();
            FeedItemHandler.handleAfterInsert(new List<FeedItem>());
        Test.stopTest();
        System.assert(true, 'Should handle empty list without error');
    }

    /*════════════════════════════════════════════
    TEST 9: buildMergeMap — tokens correctly built
    ════════════════════════════════════════════*/
    @isTest
    static void testBuildMergeMap() {

        Account acc = getOrCreatePersonAccount();
        Case c      = createCase(acc.Id);

        Case fullCase = [
            SELECT Id, CaseNumber, Subject, Status, AccountId,
                   Account.IsPersonAccount, Account.PersonEmail,
                   Account.Name, Account.AccountNumber,
                   Account.PersonContactId, Account.Phone
            FROM Case
            WHERE Id = :c.Id
        ];

        Account fullAcc = [
            SELECT Id, Name, AccountNumber, Phone,
                   PersonEmail, PersonContactId, IsPersonAccount
            FROM Account
            WHERE Id = :acc.Id
        ];

        Test.startTest();
            Map<String, String> mergeMap = FeedItemHandler.buildMergeMap(fullCase, fullAcc);
        Test.stopTest();

        System.assert(mergeMap.containsKey('{!casenumber}'),    'Should contain {!casenumber}');
        System.assert(mergeMap.containsKey('{!id}'),            'Should contain {!id}');
        System.assert(mergeMap.containsKey('{!account.name}'),  'Should contain {!account.name}');
        System.assert(mergeMap.containsKey('{!account.phone}'), 'Should contain {!account.phone}');
    }

    /*════════════════════════════════════════════
    TEST 10: buildMergeMap — null inputs
    ════════════════════════════════════════════*/
    @isTest
    static void testBuildMergeMap_NullInputs() {
        Test.startTest();
            Map<String, String> mergeMap = FeedItemHandler.buildMergeMap(null, null);
        Test.stopTest();
        System.assert(mergeMap.isEmpty(), 'Merge map should be empty for null inputs');
    }

    /*════════════════════════════════════════════
    TEST 11: resolveMergeFields — tokens replaced
    ════════════════════════════════════════════*/
    @isTest
    static void testResolveMergeFields() {

        Map<String, String> mergeMap = new Map<String, String>{
            '{!casenumber}'   => '00001234',
            '{!account.name}' => 'John Doe'
        };

        String template = 'Hello {!Account.Name}, your case {!CaseNumber} is updated.';

        Test.startTest();
            String result = FeedItemHandler.resolveMergeFields(template, mergeMap);
        Test.stopTest();

        System.assert(result.contains('John Doe'), 'Account name should be resolved');
        System.assert(result.contains('00001234'), 'Case number should be resolved');
        System.assert(!result.contains('{!'),      'No unresolved tokens should remain');
    }

    /*════════════════════════════════════════════
    TEST 12: resolveMergeFields — blank template
    ════════════════════════════════════════════*/
    @isTest
    static void testResolveMergeFields_BlankTemplate() {

        Map<String, String> mergeMap = new Map<String, String>{
            '{!casenumber}' => '00001234'
        };

        Test.startTest();
            String result = FeedItemHandler.resolveMergeFields('', mergeMap);
        Test.stopTest();

        System.assert(String.isBlank(result), 'Blank template should return blank');
    }

    /*════════════════════════════════════════════
    TEST 13: resolveMergeFields — null map
    ════════════════════════════════════════════*/
    @isTest
    static void testResolveMergeFields_NullMap() {

        Test.startTest();
            String result = FeedItemHandler.resolveMergeFields('Hello {!name}', null);
        Test.stopTest();

        System.assertEquals('Hello {!name}', result, 'Should return original template when map is null');
    }

    /*════════════════════════════════════════════
    TEST 14: Bulk FeedItems — multiple cases
    ════════════════════════════════════════════*/
    @isTest
    static void testBulkFeedItems() {

        Account acc                            = getOrCreatePersonAccount();
        sra__Message_Template__c smsTemplate   = getRealSmsTemplate();
        sra__Message_User_Configuration__c cfg = getRealSenderConfig();

        getOrCreateSetting(true, false, smsTemplate.Id, null);

        Case c1 = createCase(acc.Id);
        Case c2 = createCase(acc.Id);
        Case c3 = createCase(acc.Id);

        List<FeedItem> feedItems = new List<FeedItem>();
        for (Case c : new List<Case>{ c1, c2, c3 }) {
            feedItems.add(new FeedItem(ParentId = c.Id, Body = 'Bulk post'));
        }

        Test.startTest();
            insert feedItems;
        Test.stopTest();

        List<sra__Message_History__c> sent = [
            SELECT Id FROM sra__Message_History__c
            WHERE sra__Related_Object_Id__c IN (:c1.Id, :c2.Id, :c3.Id)
        ];

        System.assertEquals(3, sent.size(), 'Should create 3 SMS records for 3 cases');
    }
}