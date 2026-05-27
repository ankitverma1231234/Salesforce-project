@IsTest
public class MessageHistoryHandlerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;
        
        // Create message template
        sra__Message_Template__c template = new sra__Message_Template__c(
            Name = 'autoOutboundMessage',
            sra__Object_Name__c = 'sra__Message_History__c',
            sra__Template_Body__c = 'Thank you for your message. We will get back to you soon.'
        );
        insert template;
        
        // NOTE: We cannot create Custom Metadata in tests without using Test.loadData()
        // The handler should handle the case where custom metadata doesn't exist
    }
    
    // Test first inbound message - with default time window
    @IsTest
    static void testFirstInboundMessage() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Create first inbound message
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Account__c = acc.Id,
            sra__Sender_Number__c = '+1234567890',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c = 'Hello'
        );
        
        insert inboundMsg;
        
        Test.stopTest();
        
        // Query for outbound messages
        List<sra__Message_History__c> outboundMessages = [
            SELECT Id, sra__Message_Body__c, sra__Account__c,
                   sra__Sender_Number__c, sra__Receiver_Number__c
            FROM sra__Message_History__c 
            WHERE sra__Type__c = 'Outbound'
            AND sra__Account__c = :acc.Id
        ];
        
        // First inbound message should always create an outbound reply
        System.assertEquals(1, outboundMessages.size(), 'One outbound message should be created for first inbound');
        System.assertEquals('+0987654321', outboundMessages[0].sra__Sender_Number__c, 'Sender number should match receiver number of inbound');
        System.assertEquals('+1234567890', outboundMessages[0].sra__Receiver_Number__c, 'Receiver number should match sender number of inbound');
        
        // Check message content
        String expectedMessage = 'Thank you for your message. We will get back to you soon.';
        System.assertEquals(expectedMessage, outboundMessages[0].sra__Message_Body__c, 'Message body should match template');
    }
    
    // Test when no template exists
    @IsTest
    static void testNoTemplateFound() {
        // Delete template to simulate no template scenario
        delete [SELECT Id FROM sra__Message_Template__c WHERE Name = 'autoOutboundMessage'];
        
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Account__c = acc.Id,
            sra__Sender_Number__c = '+1234567890',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c = 'Hello'
        );
        
        insert inboundMsg;
        
        Test.stopTest();
        
        // Verify no outbound messages created
        List<sra__Message_History__c> outboundMessages = [
            SELECT Id FROM sra__Message_History__c 
            WHERE sra__Type__c = 'Outbound'
        ];
        
        System.assertEquals(0, outboundMessages.size(), 'No outbound messages should be created when template is missing');
    }
    
    // Test when template body is blank
    @IsTest
    static void testBlankTemplateBody() {
        // Update template with blank body
        sra__Message_Template__c template = [
            SELECT Id FROM sra__Message_Template__c 
            WHERE Name = 'autoOutboundMessage' 
            LIMIT 1
        ];
        template.sra__Template_Body__c = '';
        update template;
        
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Account__c = acc.Id,
            sra__Sender_Number__c = '+1234567890',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c = 'Hello'
        );
        
        insert inboundMsg;
        
        Test.stopTest();
        
        List<sra__Message_History__c> outboundMessages = [
            SELECT Id FROM sra__Message_History__c 
            WHERE sra__Type__c = 'Outbound'
        ];
        
        System.assertEquals(0, outboundMessages.size(), 'No outbound messages should be created when template body is blank');
    }
    
    // Test second inbound message - behavior depends on time
    @IsTest
    static void testSecondInboundMessage() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // First create a message so this is not the first inbound
        sra__Message_History__c firstInbound = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Account__c = acc.Id,
            sra__Sender_Number__c = '+1234567890',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c = 'First Message'
        );
        insert firstInbound;
        
        Test.startTest();
        
        // Create second inbound message
        sra__Message_History__c secondInbound = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Account__c = acc.Id,
            sra__Sender_Number__c = '+1234567890',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c = 'Second Message'
        );
        
        insert secondInbound;
        
        Test.stopTest();
        
        // Count outbound messages for this account
        List<sra__Message_History__c> outboundMessages = [
            SELECT Id FROM sra__Message_History__c 
            WHERE sra__Type__c = 'Outbound'
            AND sra__Account__c = :acc.Id
        ];
        
        // Should have at least 1 outbound (from the first inbound)
        // Second inbound will only create outbound if it's off-hours
        System.assert(outboundMessages.size() >= 1, 'Should have at least one outbound message');
    }
    
    // Test outbound messages are not processed
    @IsTest
    static void testOutboundMessagesIgnored() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Create outbound message (should be ignored)
        sra__Message_History__c outboundMsg = new sra__Message_History__c(
            sra__Type__c = 'Outbound',
            sra__Account__c = acc.Id,
            sra__Sender_Number__c = '+0987654321',
            sra__Receiver_Number__c = '+1234567890',
            sra__Message_Body__c = 'Manual Reply'
        );
        
        insert outboundMsg;
        
        Test.stopTest();
        
        // Count all outbound messages
        List<sra__Message_History__c> allOutboundMessages = [
            SELECT Id, sra__Message_Body__c 
            FROM sra__Message_History__c 
            WHERE sra__Type__c = 'Outbound'
            AND sra__Account__c = :acc.Id
        ];
        
        // Check if any are auto-replies
        Integer autoReplyCount = 0;
        String autoReplyText = 'Thank you for your message. We will get back to you soon.';
        for (sra__Message_History__c msg : allOutboundMessages) {
            if (msg.sra__Message_Body__c == autoReplyText) {
                autoReplyCount++;
            }
        }
        
        System.assertEquals(0, autoReplyCount, 'No auto-reply should be created for outbound message triggers');
    }
    
    // Test messages without account are ignored
    @IsTest
    static void testMessagesWithoutAccount() {
        Test.startTest();
        
        // Create inbound message without account
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Account__c = null,
            sra__Sender_Number__c = '+1234567890',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c = 'Hello'
        );
        
        insert inboundMsg;
        
        Test.stopTest();
        
        List<sra__Message_History__c> outboundMessages = [
            SELECT Id FROM sra__Message_History__c 
            WHERE sra__Type__c = 'Outbound'
        ];
        
        System.assertEquals(0, outboundMessages.size(), 'No outbound messages should be created for messages without account');
    }
    
    // Test bulk processing with multiple accounts
    @IsTest
    static void testBulkProcessingMultipleAccounts() {
        // Create additional accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 1; i <= 3; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
        
        Test.startTest();
        
        List<sra__Message_History__c> inboundMessages = new List<sra__Message_History__c>();
        for (Account acc : accounts) {
            inboundMessages.add(new sra__Message_History__c(
                sra__Type__c = 'Inbound',
                sra__Account__c = acc.Id,
                sra__Sender_Number__c = '+1234567890',
                sra__Receiver_Number__c = '+0987654321',
                sra__Message_Body__c = 'Hello from ' + acc.Name
            ));
        }
        
        insert inboundMessages;
        
        Test.stopTest();
        
        // Count outbound messages per account
        Map<Id, Integer> accountOutboundCount = new Map<Id, Integer>();
        for (sra__Message_History__c msg : [
            SELECT Id, sra__Account__c 
            FROM sra__Message_History__c 
            WHERE sra__Type__c = 'Outbound'
        ]) {
            Integer currentCount = accountOutboundCount.containsKey(msg.sra__Account__c) ? 
                accountOutboundCount.get(msg.sra__Account__c) : 0;
            accountOutboundCount.put(msg.sra__Account__c, currentCount + 1);
        }
        
        // Each account should have one outbound message (first inbound for each)
        for (Account acc : accounts) {
            System.assert(accountOutboundCount.containsKey(acc.Id), 'Account should have outbound message');
            System.assertEquals(1, accountOutboundCount.get(acc.Id), 'Each account should have one outbound message');
        }
    }
    
    // Test reentrancy prevention with mixed record types
    @IsTest
    static void testMixedMessagesBulkInsert() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        List<sra__Message_History__c> messages = new List<sra__Message_History__c>();
        
        // Add one inbound message (should trigger auto-reply)
        messages.add(new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Account__c = acc.Id,
            sra__Sender_Number__c = '+1234567890',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c = 'First Inbound'
        ));
        
        // Add an outbound message (should be ignored)
        messages.add(new sra__Message_History__c(
            sra__Type__c = 'Outbound',
            sra__Account__c = acc.Id,
            sra__Sender_Number__c = '+0987654321',
            sra__Receiver_Number__c = '+1234567890',
            sra__Message_Body__c = 'Manual Outbound'
        ));
        
        // Add another inbound without account (should be ignored)
        messages.add(new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Account__c = null,
            sra__Sender_Number__c = '+1234567890',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c = 'No Account'
        ));
        
        insert messages;
        
        Test.stopTest();
        
        // Count auto-reply messages
        List<sra__Message_History__c> autoReplies = [
            SELECT Id, sra__Message_Body__c 
            FROM sra__Message_History__c 
            WHERE sra__Type__c = 'Outbound'
            AND sra__Account__c = :acc.Id
        ];
        
        Integer autoReplyCount = 0;
        String autoReplyText = 'Thank you for your message. We will get back to you soon.';
        for (sra__Message_History__c msg : autoReplies) {
            if (msg.sra__Message_Body__c == autoReplyText) {
                autoReplyCount++;
            }
        }
        
        System.assertEquals(1, autoReplyCount, 'Should only create one auto-reply for the valid inbound message');
    }
    
    // Test handler directly with empty list
    @IsTest
    static void testDirectHandlerCallEmptyList() {
        Test.startTest();
        
        // Call handler directly with empty list
        MessageHistoryHandler.handleInboundMessages(new List<sra__Message_History__c>());
        
        Test.stopTest();
        
        // No assertions needed, just ensuring no exceptions
        System.assert(true, 'Handler should handle empty list without errors');
    }
    
    // Test the trigger context
    @IsTest
    static void testTriggerContext() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Create a message to fire the trigger
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Account__c = acc.Id,
            sra__Sender_Number__c = '+1234567890',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c = 'Trigger Test'
        );
        
        insert inboundMsg;
        
        Test.stopTest();
        
        // Verify trigger executed
        List<sra__Message_History__c> outboundMessages = [
            SELECT Id FROM sra__Message_History__c 
            WHERE sra__Type__c = 'Outbound'
            AND sra__Account__c = :acc.Id
        ];
        
        System.assert(outboundMessages.size() > 0, 'Trigger should have created outbound message');
    }
}