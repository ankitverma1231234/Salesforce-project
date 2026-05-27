@isTest
private class CaseActivityTriggerTest {
    
    @testSetup
    static void setup() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account for Case'
        );
        insert testAccount;
        
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;
    }
    
    @isTest
    static void testAfterInsertWithAccount() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create Case records with Account
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            cases.add(new Case(
                Subject = 'Test Case ' + i,
                Status = 'New',
                Origin = 'Phone',
                AccountId = acc.Id
            ));
        }
        
        Test.startTest();
        insert cases;
        Test.stopTest();
        
        // Verify records were inserted
        List<Case> insertedRecords = [
            SELECT Id, AccountId 
            FROM Case 
            WHERE AccountId = :acc.Id
        ];
        System.assertEquals(5, insertedRecords.size(), 'Should have 5 case records');
    }
    
    @isTest
    static void testAfterInsertWithoutAccount() {
        // Create Case records without Account
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            cases.add(new Case(
                Subject = 'Test Case Without Account ' + i,
                Status = 'New',
                Origin = 'Email'
                // No AccountId specified
            ));
        }
        
        Test.startTest();
        insert cases;
        Test.stopTest();
        
        // Verify records were inserted (no errors should occur)
        List<Case> insertedRecords = [
            SELECT Id, AccountId 
            FROM Case 
            WHERE AccountId = null
        ];
        System.assertEquals(3, insertedRecords.size(), 'Should have 3 cases without account');
    }
    
    @isTest
    static void testAfterInsertWithContact() {
        // Get test data
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        // Create Case with both Account and Contact
        Case testCase = new Case(
            Subject = 'Test Case With Contact',
            Status = 'New',
            Origin = 'Web',
            AccountId = acc.Id,
            ContactId = con.Id
        );
        
        Test.startTest();
        insert testCase;
        Test.stopTest();
        
        // Verify case was inserted
        Case insertedCase = [
            SELECT Id, AccountId, ContactId 
            FROM Case 
            WHERE Id = :testCase.Id
        ];
        System.assertEquals(acc.Id, insertedCase.AccountId, 'Case should be related to account');
        System.assertEquals(con.Id, insertedCase.ContactId, 'Case should be related to contact');
    }
    
    @isTest
    static void testBulkInsert() {
        // Create multiple accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(Name = 'Bulk Test Account ' + i));
        }
        insert accounts;
        
        // Create bulk Case records
        List<Case> cases = new List<Case>();
        for (Account acc : accounts) {
            for (Integer i = 0; i < 50; i++) {
                cases.add(new Case(
                    Subject = 'Bulk Test Case ' + i,
                    Status = 'New',
                    Origin = 'Phone',
                    AccountId = acc.Id
                ));
            }
        }
        
        Test.startTest();
        insert cases;
        Test.stopTest();
        
        // Verify bulk insert
        List<Case> insertedRecords = [
            SELECT Id 
            FROM Case 
            WHERE AccountId IN :accounts
        ];
        System.assertEquals(150, insertedRecords.size(), 'Should have 150 case records');
    }
    
    @isTest
    static void testMixedAccountScenario() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create mix of cases with and without accounts
        List<Case> cases = new List<Case>();
        
        // With Account
        for (Integer i = 0; i < 3; i++) {
            cases.add(new Case(
                Subject = 'Case With Account ' + i,
                Status = 'New',
                Origin = 'Email',
                AccountId = acc.Id
            ));
        }
        
        // Without Account
        for (Integer i = 0; i < 2; i++) {
            cases.add(new Case(
                Subject = 'Case Without Account ' + i,
                Status = 'New',
                Origin = 'Web'
            ));
        }
        
        Test.startTest();
        insert cases;
        Test.stopTest();
        
        // Verify all records inserted
        List<Case> allRecords = [
            SELECT Id, AccountId 
            FROM Case
        ];
        System.assertEquals(5, allRecords.size(), 'Should have 5 total case records');
        
        List<Case> withAccount = [
            SELECT Id 
            FROM Case 
            WHERE AccountId = :acc.Id
        ];
        System.assertEquals(3, withAccount.size(), 'Should have 3 cases with account');
    }
    
    @isTest
    static void testDifferentCaseOrigins() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create cases with different origins
        List<Case> cases = new List<Case>();
        
        cases.add(new Case(
            Subject = 'Phone Case',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id
        ));
        
        cases.add(new Case(
            Subject = 'Email Case',
            Status = 'New',
            Origin = 'Email',
            AccountId = acc.Id
        ));
        
        cases.add(new Case(
            Subject = 'Web Case',
            Status = 'New',
            Origin = 'Web',
            AccountId = acc.Id
        ));
        
        Test.startTest();
        insert cases;
        Test.stopTest();
        
        // Verify cases with different origins
        List<Case> insertedRecords = [
            SELECT Id, Origin 
            FROM Case 
            WHERE AccountId = :acc.Id
        ];
        System.assertEquals(3, insertedRecords.size(), 'Should have 3 cases with different origins');
    }
    
    @isTest
    static void testDifferentCaseStatuses() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create cases with different statuses
        List<Case> cases = new List<Case>();
        
        cases.add(new Case(
            Subject = 'New Case',
            Status = 'New',
            Origin = 'Phone',
            AccountId = acc.Id
        ));
        
        cases.add(new Case(
            Subject = 'Working Case',
            Status = 'Working',
            Origin = 'Email',
            AccountId = acc.Id
        ));
        
        cases.add(new Case(
            Subject = 'Escalated Case',
            Status = 'Escalated',
            Origin = 'Web',
            AccountId = acc.Id
        ));
        
        Test.startTest();
        insert cases;
        Test.stopTest();
        
        // Verify cases with different statuses
        List<Case> insertedRecords = [
            SELECT Id, Status 
            FROM Case 
            WHERE AccountId = :acc.Id
        ];
        System.assertEquals(3, insertedRecords.size(), 'Should have 3 cases with different statuses');
    }
    
    @isTest
    static void testCaseWithPriority() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create cases with different priorities
        List<Case> cases = new List<Case>();
        
        cases.add(new Case(
            Subject = 'High Priority Case',
            Status = 'New',
            Origin = 'Phone',
            Priority = 'High',
            AccountId = acc.Id
        ));
        
        cases.add(new Case(
            Subject = 'Medium Priority Case',
            Status = 'New',
            Origin = 'Email',
            Priority = 'Medium',
            AccountId = acc.Id
        ));
        
        cases.add(new Case(
            Subject = 'Low Priority Case',
            Status = 'New',
            Origin = 'Web',
            Priority = 'Low',
            AccountId = acc.Id
        ));
        
        Test.startTest();
        insert cases;
        Test.stopTest();
        
        // Verify cases with different priorities
        List<Case> insertedRecords = [
            SELECT Id, Priority 
            FROM Case 
            WHERE AccountId = :acc.Id
        ];
        System.assertEquals(3, insertedRecords.size(), 'Should have 3 cases with different priorities');
    }
}