@isTest(SeeAllData=true)
public class CaseAutoCreateQueueableTest {
@isTest
    static void testExecuteWithValidCaseIds() {
        List<Account> existingAccounts = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail != null
            LIMIT 1
        ];

        if (existingAccounts.isEmpty()) {
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();

            Account testAcc = new Account(
                FirstName         = 'Test',
                LastName          = 'User',
                RecordTypeId      = personAccountRT,
                PersonEmail       = 'test.user@example.com',
                PersonMobilePhone = '9876543210'
            );
            insert testAcc;

            existingAccounts = [
                SELECT Id, PersonContactId
                FROM Account
                WHERE Id = :testAcc.Id
            ];
        }

        Account acc = existingAccounts[0];

        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            testCases.add(new Case(
                AccountId    = acc.Id,
                ContactId    = acc.PersonContactId,
                Subject      = 'Test Case Subject ' + i,
                Description  = 'Test Case Description ' + i,
                Status       = 'New',
                Priority     = 'Medium',
                Case_Type__c = 'Portal Messages'
            ));
        }
        insert testCases;

        Set<Id> caseIds = new Map<Id, Case>(testCases).keySet();

        Test.startTest();
            CaseAutoCreateQueueablePortalUserActOnIt queueable =
                new CaseAutoCreateQueueablePortalUserActOnIt(caseIds);
            System.enqueueJob(queueable);
        Test.stopTest();

        List<Case> fetchedCases = [
            SELECT Id, AccountId, ContactId, Subject
            FROM Case
            WHERE Id IN :caseIds
        ];
        System.assertEquals(testCases.size(), fetchedCases.size(),
            'All source cases should exist after queueable execution');
    }

    @isTest
    static void testExecuteWithEmptyCaseIds() {
        Set<Id> emptyCaseIds = new Set<Id>();

        Test.startTest();
            CaseAutoCreateQueueablePortalUserActOnIt queueable =
                new CaseAutoCreateQueueablePortalUserActOnIt(emptyCaseIds);
            System.enqueueJob(queueable);
        Test.stopTest();

        List<Case> fetchedCases = [SELECT Id FROM Case WHERE Id IN :emptyCaseIds];
        System.assertEquals(0, fetchedCases.size(),
            'No cases should be returned for an empty Id set');
    }

    @isTest
    static void testExecuteWithSingleCaseId() {
        List<Account> existingAccounts = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail != null
            LIMIT 1
        ];

        if (existingAccounts.isEmpty()) {
            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();

            Account testAcc = new Account(
                FirstName         = 'Single',
                LastName          = 'User',
                RecordTypeId      = personAccountRT,
                PersonEmail       = 'single.user@example.com',
                PersonMobilePhone = '1234567890'
            );
            insert testAcc;

            existingAccounts = [
                SELECT Id, PersonContactId
                FROM Account
                WHERE Id = :testAcc.Id
            ];
        }

        Account acc = existingAccounts[0];

        Case singleCase = new Case(
            AccountId    = acc.Id,
            ContactId    = acc.PersonContactId,
            Subject      = 'Single Case Subject',
            Description  = 'Single Case Description',
            Status       = 'New',
            Priority     = 'Medium',
            Case_Type__c = 'Portal Messages'
        );
        insert singleCase;

        Set<Id> singleCaseIdSet = new Set<Id>{ singleCase.Id };

        Test.startTest();
            CaseAutoCreateQueueablePortalUserActOnIt queueable =
                new CaseAutoCreateQueueablePortalUserActOnIt(singleCaseIdSet);
            System.enqueueJob(queueable);
        Test.stopTest();

        List<Case> fetchedCases = [SELECT Id FROM Case WHERE Id = :singleCase.Id];
        System.assertEquals(1, fetchedCases.size(),
            'The single source case should still exist');
    }

    @isTest
    static void testConstructorSetsIds() {
        List<Case> cases = [SELECT Id FROM Case LIMIT 5];
        Set<Id> caseIds = new Map<Id, Case>(cases).keySet();

        Test.startTest();
            CaseAutoCreateQueueablePortalUserActOnIt queueable =
                new CaseAutoCreateQueueablePortalUserActOnIt(caseIds);
            Id jobId = System.enqueueJob(queueable);
        Test.stopTest();

        System.assertNotEquals(null, jobId,
            'Job ID should be returned after enqueuing');
    }
}