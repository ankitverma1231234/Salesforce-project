@isTest(SeeAllData=true)
private class CaseAutoCreateSubscriberPortalCaseTest {

    // =========================================================
    // HELPER: Get existing Business Account
    // =========================================================
    private static Account getBusinessAccount() {
        List<Account> existing = [
            SELECT Id FROM Account
            WHERE IsPersonAccount = false
            AND IsDeleted = false
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        Id recordTypeId = getBusinessAccountRecordTypeId();
        Account acc = new Account(Name = 'Test Business Account');
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
    // TEST 1: Valid caseId → duplicate created
    // =========================================================
    @isTest
    static void testSubscriberValidCaseId() {
        Account acc = getBusinessAccount();
        Case sourceCase = new Case(AccountId = acc.Id,
            Subject = 'Subscriber Valid Test',
            Description = 'Testing valid caseId',
            Status = 'New', Priority = 'Medium');
        insert sourceCase;

        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        Database.SaveResult sr = EventBus.publish(
            new Case_Auto_Create_Event__e(Source_Case_Id__c = sourceCase.Id)
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert(sr.isSuccess(), 'Event must publish successfully');
        System.assertEquals(beforeCount + 1,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            '1 duplicate expected');

        Case dup = [
            SELECT Subject, Description, Status, Priority, AccountId
            FROM Case
            WHERE AccountId = :acc.Id AND Id != :sourceCase.Id
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assertEquals('Subscriber Valid Test', dup.Subject);
        System.assertEquals('Testing valid caseId',  dup.Description);
        System.assertEquals('New',    dup.Status,   'Status forced to New');
        System.assertEquals('Medium', dup.Priority, 'Priority forced to Medium');
        System.assertEquals(acc.Id,   dup.AccountId);
    }

    // =========================================================
    // TEST 2: Null caseId → no job enqueued
    // =========================================================
    @isTest
    static void testSubscriberNullCaseIdSkipped() {
        Account acc = getBusinessAccount();
        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        Database.SaveResult sr = EventBus.publish(
            new Case_Auto_Create_Event__e(Source_Case_Id__c = null)
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assert(sr.isSuccess(), 'Event must publish even with null Id');
        System.assertEquals(beforeCount,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No case when Source_Case_Id__c is null');
    }

    // =========================================================
    // TEST 3: Multiple events → bulk duplicates
    // =========================================================
    @isTest
    static void testSubscriberMultipleEvents() {
        Account acc = getBusinessAccount();

        List<Case> sourceCases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            sourceCases.add(new Case(AccountId = acc.Id,
                Subject = 'Multi Event Case ' + i,
                Description = 'Multi Desc ' + i,
                Status = 'New', Priority = 'High'));
        }
        insert sourceCases;
        Set<Id> sourceIds = new Map<Id, Case>(sourceCases).keySet();

        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        List<Case_Auto_Create_Event__e> events = new List<Case_Auto_Create_Event__e>();
        for (Case c : sourceCases) {
            events.add(new Case_Auto_Create_Event__e(Source_Case_Id__c = c.Id));
        }
        List<Database.SaveResult> results = EventBus.publish(events);
        Test.getEventBus().deliver();
        Test.stopTest();

        for (Database.SaveResult sr : results) {
            System.assert(sr.isSuccess(), 'All events must publish successfully');
        }
        System.assertEquals(beforeCount + 3,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            '3 duplicates expected');

        for (Case dup : [SELECT Status, Priority FROM Case
                         WHERE AccountId = :acc.Id AND Id NOT IN :sourceIds
                         ORDER BY CreatedDate DESC LIMIT 3]) {
            System.assertEquals('New',    dup.Status,   'Forced Status = New');
            System.assertEquals('Medium', dup.Priority, 'Forced Priority = Medium');
        }
    }

    // =========================================================
    // TEST 4: Mixed null and valid events
    // =========================================================
    @isTest
    static void testSubscriberMixedNullAndValidEvents() {
        Account acc = getBusinessAccount();
        Case sourceCase = new Case(AccountId = acc.Id,
            Subject = 'Mixed Event Valid Case',
            Description = 'Only this duplicates',
            Status = 'New', Priority = 'Low');
        insert sourceCase;

        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        EventBus.publish(new List<Case_Auto_Create_Event__e>{
            new Case_Auto_Create_Event__e(Source_Case_Id__c = null),
            new Case_Auto_Create_Event__e(Source_Case_Id__c = sourceCase.Id),
            new Case_Auto_Create_Event__e(Source_Case_Id__c = null)
        });
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(beforeCount + 1,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            '1 duplicate — nulls skipped');
    }

    // =========================================================
    // TEST 5: Dangling caseId (deleted) → no insert
    // =========================================================
    @isTest
    static void testSubscriberCaseIdNotFound() {
        Account acc = getBusinessAccount();
        Case ghostCase = new Case(AccountId = acc.Id,
            Subject = 'Ghost Case', Status = 'New', Priority = 'Low');
        insert ghostCase;
        Id ghostId = ghostCase.Id;
        delete ghostCase;

        Integer beforeCount = [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id];

        Test.startTest();
        EventBus.publish(
            new Case_Auto_Create_Event__e(Source_Case_Id__c = ghostId)
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals(beforeCount,
            [SELECT COUNT() FROM Case WHERE AccountId = :acc.Id],
            'No case when source no longer exists');
    }
}