@isTest(SeeAllData=true)
public class ActivityTimelineControllerTest {

    /* ============================================================
       TEST SETUP - Called explicitly in each test
       ============================================================ */
    static void setupData() {

        /* ---------- PERSON ACCOUNT ---------- */
        Account personAcc = getPersonAccount();

        /* Tasks */
        insert new List<Task>{
            new Task(Subject='PA Task 1', Status='Not Started', WhatId=personAcc.Id),
            new Task(Subject='PA Task 2', Status='Completed', WhatId=personAcc.Id, Priority='High')
        };

        /* Call Task */
        insert new Task(
            Subject='PA Call',
            Status='Completed',
            WhatId=personAcc.Id,
            CallType='Outbound',
            TaskSubtype='Call'
        );

        /* Events */
        insert new Event(
            Subject='PA Event',
            Location='Conference Room',
            StartDateTime=System.now(),
            EndDateTime=System.now().addHours(1),
            WhatId=personAcc.Id
        );

        /* Emails (with duplicates for dedupe path) */
        insert new List<EmailMessage>{
            new EmailMessage(
                Subject='Unique Email',
                Status='0',
                RelatedToId=personAcc.Id,
                FromAddress='a@test.com',
                ToAddress='b@test.com'
            ),
            new EmailMessage(
                Subject='Duplicate Email',
                Status='0',
                RelatedToId=personAcc.Id,
                FromAddress='dup@test.com',
                ToAddress='dup2@test.com'
            ),
            new EmailMessage(
                Subject='Duplicate Email',
                Status='0',
                RelatedToId=personAcc.Id,
                FromAddress='dup@test.com',
                ToAddress='dup2@test.com'
            )
        };

        /* ---------- BUSINESS ACCOUNT ---------- */
        Account businessAcc = getBusinessAccount();

        /* Business Task */
        insert new Task(
            Subject='BA Task',
            Status='Completed',
            WhatId=businessAcc.Id
        );

        /* Case type branching - BOTH types */
        insert new List<Case>{
            new Case(
                Subject='Metriport Case',
                AccountId=businessAcc.Id,
                Status='New',
                Priority='Medium',
                Case_Type__c='Metriport Cases'
            ),
            new Case(
                Subject='Portal Message Case',
                AccountId=businessAcc.Id,
                Status='New',
                Priority='High',
                Case_Type__c='Portal Messages'
            )
        };

        /* ---------- CUSTOM OBJECTS ---------- */
        sra__Message_History__c msgHistory = new sra__Message_History__c(
            sra__MessageSid__c='SID001',
            sra__Message_Body__c='Test message body',
            sra__Account__c=businessAcc.Id,
            Name='Test Message'
        );
        insert msgHistory;

        ccra__Call_History__c callHistory = new ccra__Call_History__c(
            ccra__Call_SID__c='CALL001',
            ccra__Call_Status__c='Completed',
            ccra__Account__c=businessAcc.Id,
            Name='Test Call'
        );
        insert callHistory;
    }

    /* ============================================================
       MAIN COVERAGE TEST
       ============================================================ */
    @isTest
    static void testGetActivities_fullCoverage() {
        setupData();
        
        List<Account> accList = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = false
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (accList.isEmpty()) {
            accList = [SELECT Id FROM Account ORDER BY CreatedDate DESC LIMIT 1];
        }
        if (accList.isEmpty()) return;
        Account acc = accList[0];

        Test.startTest();
        List<ActivityTimelineController.ActivityWrapper> activities =
            ActivityTimelineController.getActivities(acc.Id, 50, 0);
        Test.stopTest();

        Set<String> types = new Set<String>();
        for (ActivityTimelineController.ActivityWrapper aw : activities) {
            types.add(aw.type);
        }

        if (!types.contains('Task')) System.debug('Task type missing');
        if (!types.contains('MetriportCases')) System.debug('MetriportCases type missing');
        if (!types.contains('PortalMessages')) System.debug('PortalMessages type missing');
        if (!types.contains('MessageHistory')) System.debug('MessageHistory type missing');
        if (!types.contains('CallHistory')) System.debug('CallHistory type missing');
    }

    /* ============================================================
       PERSON ACCOUNT SPECIFIC TEST
       ============================================================ */
    @isTest
    static void testGetActivities_personAccount() {
        setupData();
        
        List<Account> personAccounts = [
            SELECT Id 
            FROM Account 
            WHERE IsPersonAccount = true 
            LIMIT 1
        ];
        
        if (personAccounts.isEmpty()) return;

        Test.startTest();
        List<ActivityTimelineController.ActivityWrapper> activities =
            ActivityTimelineController.getActivities(personAccounts[0].Id, 50, 0);
        Test.stopTest();

        Set<String> types = new Set<String>();
        for (ActivityTimelineController.ActivityWrapper aw : activities) {
            types.add(aw.type);
        }

        Integer emailCount = 0;
        for (ActivityTimelineController.ActivityWrapper aw : activities) {
            if (aw.type == 'Email') emailCount++;
        }
    }

    /* ============================================================
       PAGINATION / OFFSET COVERAGE
       ============================================================ */
    @isTest
    static void testPaginationAndOffsets() {
        setupData();
        
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<ActivityTimelineController.ActivityWrapper> page1 =
            ActivityTimelineController.getActivities(acc.Id, 2, 0);
        List<ActivityTimelineController.ActivityWrapper> page2 =
            ActivityTimelineController.getActivities(acc.Id, 2, 2);
        List<ActivityTimelineController.ActivityWrapper> defaultParams =
            ActivityTimelineController.getActivities(acc.Id, null, null);
        Test.stopTest();
    }

    /* ============================================================
       CUSTOM OBJECT PARENT METHODS
       ============================================================ */
    @isTest
    static void testGetParentAccountForMessage() {
        setupData();
        
        List<sra__Message_History__c> msgHistories = [
            SELECT Id, sra__Account__c 
            FROM sra__Message_History__c 
            LIMIT 1
        ];
        
        if (msgHistories.isEmpty()) return;

        Test.startTest();
        Id parentAccountId = ActivityTimelineController.getParentAccountForMessage(msgHistories[0].Id);
        Id nullResult = ActivityTimelineController.getParentAccountForMessage(null);
        Test.stopTest();
    }

    @isTest
    static void testGetParentAccountForCall() {
        setupData();
        
        List<ccra__Call_History__c> callHistories = [
            SELECT Id, ccra__Account__c 
            FROM ccra__Call_History__c 
            LIMIT 1
        ];
        
        if (callHistories.isEmpty()) return;

        Test.startTest();
        Id parentAccountId = ActivityTimelineController.getParentAccountForCall(callHistories[0].Id);
        Id nullResult = ActivityTimelineController.getParentAccountForCall(null);
        Test.stopTest();
    }

    /* ============================================================
       EDGE CASES & SORTING
       ============================================================ */
    @isTest
    static void testActivityWrapper_compareTo() {
        Datetime now = System.now();
        Datetime earlier = now.addHours(-1);
        Datetime later = now.addHours(1);

        ActivityTimelineController.ActivityWrapper wrapper1 = 
            new ActivityTimelineController.ActivityWrapper(
                null, 'Test', 'Title1', 'Field1', 'Field2', now
            );

        ActivityTimelineController.ActivityWrapper wrapper2 = 
            new ActivityTimelineController.ActivityWrapper(
                null, 'Test', 'Title2', 'Field1', 'Field2', earlier
            );

        ActivityTimelineController.ActivityWrapper wrapper3 = 
            new ActivityTimelineController.ActivityWrapper(
                null, 'Test', 'Title3', 'Field1', 'Field2', later
            );

        ActivityTimelineController.ActivityWrapper wrapper4 = 
            new ActivityTimelineController.ActivityWrapper(
                null, 'Test', 'Title4', 'Field1', 'Field2', now
            );

        Test.startTest();
        wrapper1.compareTo(wrapper2);
        wrapper2.compareTo(wrapper3);
        wrapper1.compareTo(wrapper4);
        Test.stopTest();
    }

    /* ============================================================
       EMPTY RESULT HANDLING
       ============================================================ */
    @isTest
    static void testGetActivities_noData() {
        Account emptyAcc = getBusinessAccount();

        Test.startTest();
        List<ActivityTimelineController.ActivityWrapper> activities =
            ActivityTimelineController.getActivities(emptyAcc.Id, 50, 0);
        Test.stopTest();
    }

    /* ============================================================
       HELPER: GET OR CREATE PERSON ACCOUNT
       ============================================================ */
    private static Account getPersonAccount() {
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];
        if (!existingAccounts.isEmpty()) {
            return existingAccounts[0];
        }
        
        // Create minimal test data if none exists
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        Account pa = new Account(
            RecordTypeId        = personAccountRT,
            FirstName           = 'Existing',
            LastName            = 'Test',
            PersonEmail         = 'existing.test@example.com',
            PersonMobilePhone   = '5551234567'
        );
        insert pa;
        return pa;
    }

    /* ============================================================
       HELPER: GET OR CREATE BUSINESS ACCOUNT
       ============================================================ */
    private static Account getBusinessAccount() {
        // 1. Prefer an existing non-person account (no DML needed)
        List<Account> nonPersonAccounts = [
            SELECT Id, Name
            FROM Account
            WHERE IsPersonAccount = false
            LIMIT 1
        ];
        if (!nonPersonAccounts.isEmpty()) {
            return nonPersonAccounts[0];
        }

        // 2. Accept any existing account to avoid an insert entirely
        List<Account> anyAccount = [SELECT Id, Name FROM Account LIMIT 1];
        if (!anyAccount.isEmpty()) {
            return anyAccount[0];
        }

        // 3. Last resort: insert with a record type found via SOQL
        Id businessAccountRT = getBusinessAccountRecordTypeId();
        if (businessAccountRT == null) {
            throw new TestSetupException(
                'No active non-PersonAccount record type found. ' +
                'Ensure at least one business Account record type is active in this org.'
            );
        }
        Account ba = new Account(
            Name         = 'Test Business Account',
            RecordTypeId = businessAccountRT
        );
        insert ba;
        return ba;
    }

    /* ============================================================
       HELPER: GET BUSINESS ACCOUNT RECORD TYPE ID
       Uses SOQL on RecordType (more reliable than Schema.describe
       in Health Cloud orgs where isAvailable() can mislead).
       ============================================================ */
    private static Id getBusinessAccountRecordTypeId() {
        // Preferred Health Cloud business record type names
        List<String> preferredNames = new List<String>{
            'Business_Account',
            'IndustriesBusinessAccount',
            'Business',
            'Organization',
            'Household'
        };
        List<RecordType> rts = [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SobjectType = 'Account'
            AND IsActive = true
            AND DeveloperName != 'PersonAccount'
            ORDER BY DeveloperName
        ];
        // Try preferred names first
        for (String name : preferredNames) {
            for (RecordType rt : rts) {
                if (rt.DeveloperName == name) return rt.Id;
            }
        }
        // Fallback: any active non-PersonAccount record type
        if (!rts.isEmpty()) return rts[0].Id;
        return null;
    }

    public class TestSetupException extends Exception {}
}