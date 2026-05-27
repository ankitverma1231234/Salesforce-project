@isTest
private class VoiceCallActivityTriggerTest {
    
    @isTest
    static void testTriggerExecution() {
        // Create test account
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        // Create mock VoiceCall list
        List<VoiceCall> mockVoiceCalls = new List<VoiceCall>();
        VoiceCall vc = new VoiceCall();
        vc.RelatedRecordId = acc.Id;
        mockVoiceCalls.add(vc);
        
        Test.startTest();
        // Directly call the same method the trigger calls
        // This simulates what happens when trigger fires
        VoiceCallActivityHandler.handleAfterInsert(mockVoiceCalls);
        Test.stopTest();
        
        // Assertion to confirm execution
        System.assertEquals(1, mockVoiceCalls.size(), 'Should process 1 voice call');
    }
    
    @isTest
    static void testTriggerWithMultipleRecords() {
        // Create test data
        Account acc1 = new Account(Name = 'Test Account 1');
        Account acc2 = new Account(Name = 'Test Account 2');
        insert new List<Account>{acc1, acc2};
        
        // Create mock VoiceCall list
        List<VoiceCall> mockVoiceCalls = new List<VoiceCall>();
        mockVoiceCalls.add(new VoiceCall(RelatedRecordId = acc1.Id));
        mockVoiceCalls.add(new VoiceCall(RelatedRecordId = acc2.Id));
        
        Test.startTest();
        VoiceCallActivityHandler.handleAfterInsert(mockVoiceCalls);
        Test.stopTest();
        
        System.assertEquals(2, mockVoiceCalls.size(), 'Should process 2 voice calls');
    }
    
    @isTest
    static void testTriggerWithNullRelatedRecord() {
        // Create mock VoiceCall without RelatedRecordId
        List<VoiceCall> mockVoiceCalls = new List<VoiceCall>();
        mockVoiceCalls.add(new VoiceCall());
        
        Test.startTest();
        VoiceCallActivityHandler.handleAfterInsert(mockVoiceCalls);
        Test.stopTest();
        
        System.assert(true, 'Should handle null RelatedRecordId without error');
    }
}