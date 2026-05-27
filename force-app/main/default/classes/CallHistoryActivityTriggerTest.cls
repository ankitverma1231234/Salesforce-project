@isTest
private class CallHistoryActivityTriggerTest {
    
    @testSetup
    static void setup() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account for Call History'
        );
        insert testAccount;
    }
    
    @isTest
    static void testAfterInsertWithAccount() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create Call History records with Account
        List<ccra__Call_History__c> callHistories = new List<ccra__Call_History__c>();
        for (Integer i = 0; i < 5; i++) {
            callHistories.add(new ccra__Call_History__c(
                ccra__Account__c = acc.Id
                // Add other required fields if any
            ));
        }
        
        Test.startTest();
        insert callHistories;
        Test.stopTest();
        
        // Verify records were inserted
        List<ccra__Call_History__c> insertedRecords = [
            SELECT Id, ccra__Account__c 
            FROM ccra__Call_History__c 
            WHERE ccra__Account__c = :acc.Id
        ];
        System.assertEquals(5, insertedRecords.size(), 'Should have 5 call history records');
    }
    
    @isTest
    static void testAfterInsertWithoutAccount() {
        // Create Call History records without Account
        List<ccra__Call_History__c> callHistories = new List<ccra__Call_History__c>();
        for (Integer i = 0; i < 3; i++) {
            callHistories.add(new ccra__Call_History__c(
                // No Account specified
                // Add other required fields if any
            ));
        }
        
        Test.startTest();
        insert callHistories;
        Test.stopTest();
        
        // Verify records were inserted (no errors should occur)
        List<ccra__Call_History__c> insertedRecords = [
            SELECT Id, ccra__Account__c 
            FROM ccra__Call_History__c 
            WHERE ccra__Account__c = null
        ];
        System.assertEquals(3, insertedRecords.size(), 'Should have 3 call history records without account');
    }
    
    @isTest
    static void testAfterUpdate() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create another account for update test
        Account newAccount = new Account(Name = 'New Test Account');
        insert newAccount;
        
        // Create Call History record
        ccra__Call_History__c ch = new ccra__Call_History__c(
            ccra__Account__c = acc.Id
        );
        insert ch;
        
        Test.startTest();
        // Update to new account
        ch.ccra__Account__c = newAccount.Id;
        update ch;
        Test.stopTest();
        
        // Verify update
        ccra__Call_History__c updatedRecord = [
            SELECT Id, ccra__Account__c 
            FROM ccra__Call_History__c 
            WHERE Id = :ch.Id
        ];
        System.assertEquals(newAccount.Id, updatedRecord.ccra__Account__c, 'Account should be updated');
    }
    
    @isTest
    static void testBulkInsert() {
        // Create multiple accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(Name = 'Bulk Test Account ' + i));
        }
        insert accounts;
        
        // Create bulk Call History records
        List<ccra__Call_History__c> callHistories = new List<ccra__Call_History__c>();
        for (Account acc : accounts) {
            for (Integer i = 0; i < 50; i++) {
                callHistories.add(new ccra__Call_History__c(
                    ccra__Account__c = acc.Id
                ));
            }
        }
        
        Test.startTest();
        insert callHistories;
        Test.stopTest();
        
        // Verify bulk insert
        List<ccra__Call_History__c> insertedRecords = [
            SELECT Id 
            FROM ccra__Call_History__c 
            WHERE ccra__Account__c IN :accounts
        ];
        System.assertEquals(150, insertedRecords.size(), 'Should have 150 call history records');
    }
    
    @isTest
    static void testMixedAccountScenario() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create mix of records with and without accounts
        List<ccra__Call_History__c> callHistories = new List<ccra__Call_History__c>();
        
        // With Account
        for (Integer i = 0; i < 3; i++) {
            callHistories.add(new ccra__Call_History__c(
                ccra__Account__c = acc.Id
            ));
        }
        
        // Without Account
        for (Integer i = 0; i < 2; i++) {
            callHistories.add(new ccra__Call_History__c());
        }
        
        Test.startTest();
        insert callHistories;
        Test.stopTest();
        
        // Verify all records inserted
        List<ccra__Call_History__c> allRecords = [
            SELECT Id, ccra__Account__c 
            FROM ccra__Call_History__c
        ];
        System.assertEquals(5, allRecords.size(), 'Should have 5 total records');
        
        List<ccra__Call_History__c> withAccount = [
            SELECT Id 
            FROM ccra__Call_History__c 
            WHERE ccra__Account__c = :acc.Id
        ];
        System.assertEquals(3, withAccount.size(), 'Should have 3 records with account');
    }
    
    @isTest
    static void testUpdateFromNullToAccount() {
        // Create Call History record without account
        ccra__Call_History__c ch = new ccra__Call_History__c();
        insert ch;
        
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        // Update to add account
        ch.ccra__Account__c = acc.Id;
        update ch;
        Test.stopTest();
        
        // Verify update
        ccra__Call_History__c updatedRecord = [
            SELECT Id, ccra__Account__c 
            FROM ccra__Call_History__c 
            WHERE Id = :ch.Id
        ];
        System.assertEquals(acc.Id, updatedRecord.ccra__Account__c, 'Account should be added');
    }
}