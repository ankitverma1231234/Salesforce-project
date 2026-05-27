@isTest
private class EmailActivityTriggerTest {
    
    @testSetup
    static void setup() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account for Email'
        );
        insert testAccount;
        
        // Create test Case
        Case testCase = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Origin = 'Email',
            AccountId = testAccount.Id
        );
        insert testCase;
        
        // Create test Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = testAccount.Id
        );
        insert testOpp;
    }
    
    @isTest
    static void testBeforeInsertWithAccount() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create EmailMessage records with Account as RelatedTo
        List<EmailMessage> emailMessages = new List<EmailMessage>();
        for (Integer i = 0; i < 5; i++) {
            emailMessages.add(new EmailMessage(
                Subject = 'Test Email ' + i,
                TextBody = 'Test email body',
                FromAddress = 'sender@example.com',
                ToAddress = 'recipient@example.com',
                RelatedToId = acc.Id,
                Status = '0' // Draft
            ));
        }
        
        Test.startTest();
        insert emailMessages;
        Test.stopTest();
        
        // Verify records were inserted
        List<EmailMessage> insertedRecords = [
            SELECT Id, RelatedToId 
            FROM EmailMessage 
            WHERE RelatedToId = :acc.Id
        ];
        System.assertEquals(5, insertedRecords.size(), 'Should have 5 email message records');
    }
    
    @isTest
    static void testBeforeInsertWithCase() {
        // Get test case
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        // Create EmailMessage records with Case as RelatedTo
        List<EmailMessage> emailMessages = new List<EmailMessage>();
        for (Integer i = 0; i < 3; i++) {
            emailMessages.add(new EmailMessage(
                Subject = 'Test Case Email ' + i,
                TextBody = 'Test case email body',
                FromAddress = 'sender@example.com',
                ToAddress = 'recipient@example.com',
                RelatedToId = testCase.Id,
                Status = '0'
            ));
        }
        
        Test.startTest();
        insert emailMessages;
        Test.stopTest();
        
        // Verify records were inserted
        List<EmailMessage> insertedRecords = [
            SELECT Id, RelatedToId 
            FROM EmailMessage 
            WHERE RelatedToId = :testCase.Id
        ];
        System.assertEquals(3, insertedRecords.size(), 'Should have 3 email messages related to case');
    }
    
    @isTest
    static void testBeforeInsertWithOpportunity() {
        // Get test opportunity
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Create EmailMessage records with Opportunity as RelatedTo
        List<EmailMessage> emailMessages = new List<EmailMessage>();
        emailMessages.add(new EmailMessage(
            Subject = 'Opportunity Email',
            TextBody = 'Opportunity email body',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            RelatedToId = opp.Id,
            Status = '0'
        ));
        
        Test.startTest();
        insert emailMessages;
        Test.stopTest();
        
        // Verify email related to opportunity
        List<EmailMessage> insertedRecords = [
            SELECT Id, RelatedToId 
            FROM EmailMessage 
            WHERE RelatedToId = :opp.Id
        ];
        System.assertEquals(1, insertedRecords.size(), 'Should have 1 email message related to opportunity');
    }
    
    @isTest
    static void testBeforeInsertWithoutRelatedTo() {
        // Create EmailMessage records without RelatedToId
        List<EmailMessage> emailMessages = new List<EmailMessage>();
        for (Integer i = 0; i < 2; i++) {
            emailMessages.add(new EmailMessage(
                Subject = 'Test Standalone Email ' + i,
                TextBody = 'Test standalone email body',
                FromAddress = 'sender@example.com',
                ToAddress = 'recipient@example.com',
                Status = '0'
                // No RelatedToId specified
            ));
        }
        
        Test.startTest();
        insert emailMessages;
        Test.stopTest();
        
        // Verify records were inserted (no errors should occur)
        List<EmailMessage> insertedRecords = [
            SELECT Id, RelatedToId 
            FROM EmailMessage 
            WHERE RelatedToId = null
        ];
        System.assertEquals(2, insertedRecords.size(), 'Should have 2 email messages without RelatedTo');
    }
    
    @isTest
    static void testBulkInsert() {
        // Create multiple accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(Name = 'Bulk Test Account ' + i));
        }
        insert accounts;
        
        // Create bulk EmailMessage records
        List<EmailMessage> emailMessages = new List<EmailMessage>();
        for (Account acc : accounts) {
            for (Integer i = 0; i < 30; i++) {
                emailMessages.add(new EmailMessage(
                    Subject = 'Bulk Test Email ' + i,
                    TextBody = 'Bulk test email body',
                    FromAddress = 'sender@example.com',
                    ToAddress = 'recipient@example.com',
                    RelatedToId = acc.Id,
                    Status = '0'
                ));
            }
        }
        
        Test.startTest();
        insert emailMessages;
        Test.stopTest();
        
        // Verify bulk insert
        List<EmailMessage> insertedRecords = [
            SELECT Id 
            FROM EmailMessage 
            WHERE RelatedToId IN :accounts
        ];
        System.assertEquals(90, insertedRecords.size(), 'Should have 90 email message records');
    }
    
    @isTest
    static void testMixedRelatedToScenario() {
        // Get test data
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Create mix of records with different RelatedTo values
        List<EmailMessage> emailMessages = new List<EmailMessage>();
        
        // With Account
        emailMessages.add(new EmailMessage(
            Subject = 'Account Email',
            TextBody = 'Account email body',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            RelatedToId = acc.Id,
            Status = '0'
        ));
        
        // With Case
        emailMessages.add(new EmailMessage(
            Subject = 'Case Email',
            TextBody = 'Case email body',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            RelatedToId = testCase.Id,
            Status = '0'
        ));
        
        // With Opportunity
        emailMessages.add(new EmailMessage(
            Subject = 'Opportunity Email',
            TextBody = 'Opportunity email body',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            RelatedToId = opp.Id,
            Status = '0'
        ));
        
        // Without RelatedTo
        emailMessages.add(new EmailMessage(
            Subject = 'Standalone Email',
            TextBody = 'Standalone email body',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            Status = '0'
        ));
        
        Test.startTest();
        insert emailMessages;
        Test.stopTest();
        
        // Verify all records inserted
        List<EmailMessage> allRecords = [
            SELECT Id, RelatedToId 
            FROM EmailMessage
        ];
        System.assertEquals(4, allRecords.size(), 'Should have 4 total email message records');
    }
    
    @isTest
    static void testDifferentEmailStatuses() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create EmailMessage records with different statuses
        List<EmailMessage> emailMessages = new List<EmailMessage>();
        
        // Draft
        emailMessages.add(new EmailMessage(
            Subject = 'Draft Email',
            TextBody = 'Draft email body',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            RelatedToId = acc.Id,
            Status = '0'
        ));
        
        // Sent
        emailMessages.add(new EmailMessage(
            Subject = 'Sent Email',
            TextBody = 'Sent email body',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            RelatedToId = acc.Id,
            Status = '3'
        ));
        
        Test.startTest();
        insert emailMessages;
        Test.stopTest();
        
        // Verify records with different statuses
        List<EmailMessage> insertedRecords = [
            SELECT Id, Status 
            FROM EmailMessage 
            WHERE RelatedToId = :acc.Id
        ];
        System.assertEquals(2, insertedRecords.size(), 'Should have 2 email message records with different statuses');
    }
}