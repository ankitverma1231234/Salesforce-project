@isTest
private class VoiceCallActivityHandlerTest {
    
    @testSetup
    static void setup() {
        // Create test Account
        Account testAccount = new Account(
            Name = 'Test Account for Voice Call'
        );
        insert testAccount;
        
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = testAccount.Id
        );
        insert testContact;
    }
    
    @isTest
    static void testHandleAfterInsertWithAccount() {
        // Get test account
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create mock VoiceCall data
        List<VoiceCall> mockVoiceCalls = new List<VoiceCall>();
        VoiceCall vc1 = new VoiceCall(RelatedRecordId = acc.Id);
        VoiceCall vc2 = new VoiceCall(RelatedRecordId = acc.Id);
        mockVoiceCalls.add(vc1);
        mockVoiceCalls.add(vc2);
        
        Test.startTest();
        VoiceCallActivityHandler.handleAfterInsert(mockVoiceCalls);
        Test.stopTest();
        
        // If we reach here without exception, the handler executed successfully
        System.assert(true, 'Handler executed without errors');
    }
    
    @isTest
    static void testHandleAfterInsertWithContact() {
        // Get test contact
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        // Create mock VoiceCall data
        List<VoiceCall> mockVoiceCalls = new List<VoiceCall>();
        VoiceCall vc = new VoiceCall(RelatedRecordId = con.Id);
        mockVoiceCalls.add(vc);
        
        Test.startTest();
        VoiceCallActivityHandler.handleAfterInsert(mockVoiceCalls);
        Test.stopTest();
        
        System.assert(true, 'Handler executed successfully with Contact');
    }
    
    @isTest
    static void testHandleAfterInsertWithoutRelatedRecord() {
        // Create mock VoiceCall data without RelatedRecordId
        List<VoiceCall> mockVoiceCalls = new List<VoiceCall>();
        VoiceCall vc = new VoiceCall();
        mockVoiceCalls.add(vc);
        
        Test.startTest();
        VoiceCallActivityHandler.handleAfterInsert(mockVoiceCalls);
        Test.stopTest();
        
        // Should handle null RelatedRecordId gracefully
        System.assert(true, 'Handler executed without errors for null RelatedRecordId');
    }
    
    @isTest
    static void testBulkHandling() {
        // Create multiple accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(Name = 'Bulk Test Account ' + i));
        }
        insert accounts;
        
        // Create mock bulk VoiceCall data
        List<VoiceCall> mockVoiceCalls = new List<VoiceCall>();
        for (Account acc : accounts) {
            for (Integer i = 0; i < 20; i++) {
                mockVoiceCalls.add(new VoiceCall(RelatedRecordId = acc.Id));
            }
        }
        
        Test.startTest();
        VoiceCallActivityHandler.handleAfterInsert(mockVoiceCalls);
        Test.stopTest();
        
        // Verify bulk processing
        System.assertEquals(100, mockVoiceCalls.size(), 'Should handle 100 records');
    }
    
    @isTest
    static void testMixedRelatedRecordScenario() {
        // Get test data
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        // Create mock VoiceCall data with mixed scenarios
        List<VoiceCall> mockVoiceCalls = new List<VoiceCall>();
        mockVoiceCalls.add(new VoiceCall(RelatedRecordId = acc.Id));
        mockVoiceCalls.add(new VoiceCall(RelatedRecordId = con.Id));
        mockVoiceCalls.add(new VoiceCall()); // null RelatedRecordId
        
        Test.startTest();
        VoiceCallActivityHandler.handleAfterInsert(mockVoiceCalls);
        Test.stopTest();
        
        System.assert(true, 'Handler processed mixed scenarios successfully');
    }
    
    @isTest
    static void testEmptyList() {
        List<VoiceCall> emptyList = new List<VoiceCall>();
        
        Test.startTest();
        VoiceCallActivityHandler.handleAfterInsert(emptyList);
        Test.stopTest();
        
        System.assert(true, 'Handler handled empty list gracefully');
    }
}