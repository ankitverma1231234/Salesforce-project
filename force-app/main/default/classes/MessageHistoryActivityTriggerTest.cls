@IsTest
private class MessageHistoryActivityTriggerTest {
      @testSetup
    static void setup() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account for Message History'
        );
        insert testAccount;
    }
    
    @isTest
    static void testAfterInsertWithAccount() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create Message History records with Account
        List<sra__Message_History__c> messageHistories = new List<sra__Message_History__c>();
        for (Integer i = 0; i < 5; i++) {
            messageHistories.add(new sra__Message_History__c(
                sra__Account__c = acc.Id
                // Add other required fields if any
            ));
        }
        
        Test.startTest();
        insert messageHistories;
        Test.stopTest();
        
        // Verify records were inserted
        List<sra__Message_History__c> insertedRecords = [
            SELECT Id, sra__Account__c 
            FROM sra__Message_History__c 
            WHERE sra__Account__c = :acc.Id
        ];
        System.assertEquals(5, insertedRecords.size(), 'Should have 5 message history records');
    }
    
    @isTest
    static void testAfterInsertWithoutAccount() {
        // Create Message History records without Account
        List<sra__Message_History__c> messageHistories = new List<sra__Message_History__c>();
        for (Integer i = 0; i < 3; i++) {
            messageHistories.add(new sra__Message_History__c(
                // No Account specified
                // Add other required fields if any
            ));
        }
        
        Test.startTest();
        insert messageHistories;
        Test.stopTest();
        
        // Verify records were inserted (no errors should occur)
        List<sra__Message_History__c> insertedRecords = [
            SELECT Id, sra__Account__c 
            FROM sra__Message_History__c 
            WHERE sra__Account__c = null
        ];
        System.assertEquals(3, insertedRecords.size(), 'Should have 3 message history records without account');
    }
    
    @isTest
    static void testAfterUpdate() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create another account for update test
        Account newAccount = new Account(Name = 'New Test Account');
        insert newAccount;
        
        // Create Message History record
        sra__Message_History__c mh = new sra__Message_History__c(
            sra__Account__c = acc.Id
        );
        insert mh;
        
        Test.startTest();
        // Update to new account
        mh.sra__Account__c = newAccount.Id;
        update mh;
        Test.stopTest();
        
        // Verify update
        sra__Message_History__c updatedRecord = [
            SELECT Id, sra__Account__c 
            FROM sra__Message_History__c 
            WHERE Id = :mh.Id
        ];
        System.assertEquals(newAccount.Id, updatedRecord.sra__Account__c, 'Account should be updated');
    }
    
    @isTest
    static void testBulkInsert() {
        // Create multiple accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(Name = 'Bulk Test Account ' + i));
        }
        insert accounts;
        
        // Create bulk Message History records
        List<sra__Message_History__c> messageHistories = new List<sra__Message_History__c>();
        for (Account acc : accounts) {
            for (Integer i = 0; i < 50; i++) {
                messageHistories.add(new sra__Message_History__c(
                    sra__Account__c = acc.Id
                ));
            }
        }
        
        Test.startTest();
        insert messageHistories;
        Test.stopTest();
        
        // Verify bulk insert
        List<sra__Message_History__c> insertedRecords = [
            SELECT Id 
            FROM sra__Message_History__c 
            WHERE sra__Account__c IN :accounts
        ];
        System.assertEquals(150, insertedRecords.size(), 'Should have 150 message history records');
    }
    
    @isTest
    static void testMixedAccountScenario() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create mix of records with and without accounts
        List<sra__Message_History__c> messageHistories = new List<sra__Message_History__c>();
        
        // With Account
        for (Integer i = 0; i < 3; i++) {
            messageHistories.add(new sra__Message_History__c(
                sra__Account__c = acc.Id
            ));
        }
        
        // Without Account
        for (Integer i = 0; i < 2; i++) {
            messageHistories.add(new sra__Message_History__c());
        }
        
        Test.startTest();
        insert messageHistories;
        Test.stopTest();
        
        // Verify all records inserted
        List<sra__Message_History__c> allRecords = [
            SELECT Id, sra__Account__c 
            FROM sra__Message_History__c
        ];
        System.assertEquals(5, allRecords.size(), 'Should have 5 total records');
        
        List<sra__Message_History__c> withAccount = [
            SELECT Id 
            FROM sra__Message_History__c 
            WHERE sra__Account__c = :acc.Id
        ];
        System.assertEquals(3, withAccount.size(), 'Should have 3 records with account');
    }
}