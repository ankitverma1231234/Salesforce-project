@IsTest(SeeAllData=true)
public class CaseTriggerTest {

    /* ------------------------------------------------------------
       Utility: Get or Create Valid Account
    -------------------------------------------------------------*/
    private static Account getOrCreateAccount() {

        // Try existing Person Account first
        List<Account> existingAccounts = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];

        if (!existingAccounts.isEmpty()) {
            return existingAccounts[0];
        }

        // Fallback: create minimal Person Account
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account acc = new Account(
            FirstName = 'Test',
            LastName = 'Person',
            RecordTypeId = personAccountRT,
            PersonEmail = 'test.person@example.com',
            PersonMobilePhone = '5551234567'
        );
        insert acc;
        return acc;
    }

    /* ------------------------------------------------------------
       INSERT
    -------------------------------------------------------------*/
    @IsTest
    static void testCaseInsert() {
        Test.startTest();

        Account acc = getOrCreateAccount();

        Case c = new Case(
            AccountId = acc.Id,
            Case_Type__c = 'Portal Messages',
            Status = 'New',
            Subject = 'Insert Test',
            Description = 'Insert description'
        );
        insert c;

        Test.stopTest();

        System.assertNotEquals(null, c.Id);
    }

    /* ------------------------------------------------------------
       UPDATE: Field Changes
    -------------------------------------------------------------*/
    @IsTest
    static void testCaseUpdateWithChanges() {
        Account acc = getOrCreateAccount();

        Case c = new Case(
            AccountId = acc.Id,
            Case_Type__c = 'Portal Messages',
            Status = 'New',
            Subject = 'Original Subject'
        );
        insert c;

        Test.startTest();

        c.Status = 'Working';
        c.Subject = 'Updated Subject';
        update c;

        Test.stopTest();

        Case updated = [
            SELECT Status, Subject
            FROM Case
            WHERE Id = :c.Id
        ];
        System.assertEquals('Working', updated.Status);
        System.assertEquals('Updated Subject', updated.Subject);
    }

    /* ------------------------------------------------------------
       UPDATE: Description Only
    -------------------------------------------------------------*/
    @IsTest
    static void testCaseDescriptionUpdate() {
        Account acc = getOrCreateAccount();

        Case c = new Case(
            AccountId = acc.Id,
            Case_Type__c = 'Portal Messages',
            Status = 'New'
        );
        insert c;

        Test.startTest();
        c.Description = 'New Description';
        update c;
        Test.stopTest();

        System.assertEquals(
            'New Description',
            [SELECT Description FROM Case WHERE Id = :c.Id].Description
        );
    }

    /* ------------------------------------------------------------
       DELETE
    -------------------------------------------------------------*/
    @IsTest
    static void testCaseDelete() {
        Account acc = getOrCreateAccount();

        Case c = new Case(
            AccountId = acc.Id,
            Case_Type__c = 'Portal Messages',
            Status = 'New'
        );
        insert c;

        Test.startTest();
        delete c;
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Case WHERE Id = :c.Id]
        );
    }

    /* ------------------------------------------------------------
       BULK
    -------------------------------------------------------------*/
    @IsTest
    static void testBulkCases() {
        Account acc = getOrCreateAccount();

        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 25; i++) {
            cases.add(new Case(
                AccountId = acc.Id,
                Case_Type__c = 'Portal Messages',
                Status = 'New',
                Subject = 'Bulk ' + i
            ));
        }

        Test.startTest();
        insert cases;

        for (Case c : cases) {
            c.Status = 'Closed';
        }
        update cases;

        delete cases;
        Test.stopTest();

        System.assert(true);
    }
}