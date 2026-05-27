@IsTest(seeAllData=true)
public class MessageSessionHandlerTest {

    // ─────────────────────────────────────────────
    // Shared helper: ensure MessageCustomization__c exists
    // ─────────────────────────────────────────────
    private static void setupMessageCustomization() {
        MessageCustomization__c existing = MessageCustomization__c.getInstance('Message');
        if (existing == null || existing.Session_Time__c == null) {
            MessageCustomization__c setting = new MessageCustomization__c(
                Name             = 'Message',
                Session_Time__c  = 1 // 1 hour session
            );
            upsert setting Name;
        }
    }

    // ─────────────────────────────────────────────
    // Test 1: Inbound message creates session + auto-reply
    // ─────────────────────────────────────────────
    @isTest
    static void testNewInboundMessageCreatesSessionAndAutoReply() {
        setupMessageCustomization();
        Account testAccount = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c            = 'Inbound',
            sra__Sender_Number__c   = '+1111111111',
            sra__Receiver_Number__c = '+0987654321',
            sra__Account__c         = testAccount.Id,
            sra__Message_Body__c    = 'Hello, I need help',
            sra__Related_Object_Id__c = testAccount.Id
        );
        insert inboundMsg;
        Test.stopTest();

        List<Message_Session__c> sessions = [
            SELECT Id, Phone_Number__c, Session_Status__c, Start_Time__c, End_Time__c
            FROM Message_Session__c
            WHERE Phone_Number__c = '+1111111111'
        ];
        System.assertEquals(1, sessions.size(), 'One session should be created');
        System.assertEquals('Open', sessions[0].Session_Status__c, 'Session should be Open');
        System.assertNotEquals(null, sessions[0].Start_Time__c, 'Start time should be set');
        System.assertNotEquals(null, sessions[0].End_Time__c, 'End time should be set');

        sra__Message_History__c updatedMsg = [
            SELECT Id, Message_Session__c FROM sra__Message_History__c WHERE Id = :inboundMsg.Id
        ];
        System.assertEquals(sessions[0].Id, updatedMsg.Message_Session__c, 'Message should be linked');

        List<sra__Message_History__c> outbound = [
            SELECT Id, Message_Session__c FROM sra__Message_History__c
            WHERE sra__Type__c = 'Outbound' AND sra__Receiver_Number__c = '+1111111111'
        ];
        System.assertEquals(1, outbound.size(), 'One auto-reply should be sent');
        System.assertEquals(sessions[0].Id, outbound[0].Message_Session__c, 'Auto-reply linked to session');
    }

    // ─────────────────────────────────────────────
    // Test 2: Second message within window extends session (no new session)
    // ─────────────────────────────────────────────
    @isTest
    static void testMultipleMessagesExtendSession() {
        setupMessageCustomization();
        Account testAccount = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        // First message — creates session
        sra__Message_History__c firstMsg = new sra__Message_History__c(
            sra__Type__c            = 'Inbound',
            sra__Sender_Number__c   = '+2222222222',
            sra__Receiver_Number__c = '+0987654321',
            sra__Account__c         = testAccount.Id,
            sra__Message_Body__c    = 'First message'
        );
        insert firstMsg;

        Message_Session__c session = [
            SELECT Id, End_Time__c FROM Message_Session__c
            WHERE Phone_Number__c = '+2222222222' LIMIT 1
        ];
        DateTime firstEndTime = session.End_Time__c;

        Test.startTest();
        sra__Message_History__c secondMsg = new sra__Message_History__c(
            sra__Type__c            = 'Inbound',
            sra__Sender_Number__c   = '+2222222222',
            sra__Receiver_Number__c = '+0987654321',
            sra__Account__c         = testAccount.Id,
            sra__Message_Body__c    = 'Second message'
        );
        insert secondMsg;
        Test.stopTest();

        List<Message_Session__c> sessions = [
            SELECT Id, End_Time__c FROM Message_Session__c
            WHERE Phone_Number__c = '+2222222222'
        ];
        System.assertEquals(1, sessions.size(), 'Should still be only one session');

        // End time should be updated (extended)
        System.assert(
            sessions[0].End_Time__c >= firstEndTime,
            'Session end time should be extended or equal'
        );
    }

    // ─────────────────────────────────────────────
    // Test 3: Session transition — expired session gets closed, new one created
    // ─────────────────────────────────────────────
    @isTest
    static void testExpiredSessionCreatesNewSession() {
        setupMessageCustomization();
        Account testAccount = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        // Manually insert an already-expired open session
        Message_Session__c expiredSession = new Message_Session__c(
            Phone_Number__c  = '+3333333333',
            Start_Time__c    = DateTime.now().addHours(-5),
            End_Time__c      = DateTime.now().addHours(-3), // expired
            Session_Status__c = 'Open',
            Account__c       = testAccount.Id
        );
        insert expiredSession;

        Test.startTest();
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c            = 'Inbound',
            sra__Sender_Number__c   = '+3333333333',
            sra__Receiver_Number__c = '+0987654321',
            sra__Account__c         = testAccount.Id,
            sra__Message_Body__c    = 'New message after session expired'
        );
        insert inboundMsg;
        Test.stopTest();

        // Old session should be closed
        Message_Session__c closedSession = [
            SELECT Id, Session_Status__c FROM Message_Session__c WHERE Id = :expiredSession.Id
        ];
        System.assertEquals('Closed', closedSession.Session_Status__c, 'Expired session should be closed');

        // New open session should exist
        List<Message_Session__c> openSessions = [
            SELECT Id, Session_Status__c FROM Message_Session__c
            WHERE Phone_Number__c = '+3333333333' AND Session_Status__c = 'Open'
        ];
        System.assertEquals(1, openSessions.size(), 'A new open session should be created');
    }

    // ─────────────────────────────────────────────
    // Test 4: Outbound messages linked to existing open session
    // ─────────────────────────────────────────────
    @isTest
    static void testOutboundMessagesLinkedToSessions() {
        setupMessageCustomization();
        Account testAccount = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c            = 'Inbound',
            sra__Sender_Number__c   = '+4444444444',
            sra__Receiver_Number__c = '+0987654321',
            sra__Account__c         = testAccount.Id,
            sra__Message_Body__c    = 'Hello'
        );
        insert inboundMsg;

        Message_Session__c session = [
            SELECT Id FROM Message_Session__c WHERE Phone_Number__c = '+4444444444' LIMIT 1
        ];

        Test.startTest();
        sra__Message_History__c outboundMsg = new sra__Message_History__c(
            sra__Type__c            = 'Outbound',
            sra__Sender_Number__c   = '+0987654321',
            sra__Receiver_Number__c = '+4444444444',
            sra__Account__c         = testAccount.Id,
            sra__Message_Body__c    = 'Manual response'
        );
        insert outboundMsg;
        Test.stopTest();

        sra__Message_History__c updated = [
            SELECT Id, Message_Session__c FROM sra__Message_History__c WHERE Id = :outboundMsg.Id
        ];
        System.assertEquals(session.Id, updated.Message_Session__c, 'Outbound should be linked to session');
    }

    // ─────────────────────────────────────────────
    // Test 5: Missing MessageCustomization__c — early return path
    // ─────────────────────────────────────────────
    @isTest
    static void testMissingCustomSettingEarlyReturn() {
        // Delete the custom setting if it exists to hit the null/early-return branch
        List<MessageCustomization__c> settings = [
            SELECT Id FROM MessageCustomization__c WHERE Name = 'Message'
        ];
        if (!settings.isEmpty()) {
            delete settings;
        }

        Account testAccount = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c            = 'Inbound',
            sra__Sender_Number__c   = '+5555555555',
            sra__Receiver_Number__c = '+0987654321',
            sra__Account__c         = testAccount.Id,
            sra__Message_Body__c    = 'Test no config'
        );
        insert inboundMsg;
        Test.stopTest();

        // No session should be created due to early return
        List<Message_Session__c> sessions = [
            SELECT Id FROM Message_Session__c WHERE Phone_Number__c = '+5555555555'
        ];
        System.assertEquals(0, sessions.size(), 'No session should be created without config');

        setupMessageCustomization(); // restore for other tests
    }

    // ─────────────────────────────────────────────
    // Test 6: Inbound message with no account — triggers dynamic phone lookup branch
    // ─────────────────────────────────────────────
    @isTest
    static void testCreateSessionWithNullAccount() {
        setupMessageCustomization();

        Test.startTest();
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c            = 'Inbound',
            sra__Sender_Number__c   = '+6666666666',
            sra__Receiver_Number__c = '+0987654321',
            sra__Message_Body__c    = 'No account message'
            // intentionally no sra__Account__c
        );
        insert inboundMsg;
        Test.stopTest();

        // Session should still be created (with or without account match)
        List<Message_Session__c> sessions = [
            SELECT Id, Session_Status__c FROM Message_Session__c
            WHERE Phone_Number__c = '+6666666666'
        ];
        System.assertEquals(1, sessions.size(), 'Session should be created even without account');
        System.assertEquals('Open', sessions[0].Session_Status__c);
    }

    // ─────────────────────────────────────────────
    // Test 7: Only outbound messages — no inbound, linkOutboundMessagesToSessions
    //         with no matching active session (empty receiverNumbers path)
    // ─────────────────────────────────────────────
    @isTest
    static void testOutboundOnlyNoMatchingSession() {
        setupMessageCustomization();
        Account testAccount = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        // Outbound to a number with no open session — should handle gracefully
        sra__Message_History__c outboundMsg = new sra__Message_History__c(
            sra__Type__c            = 'Outbound',
            sra__Sender_Number__c   = '+0987654321',
            sra__Receiver_Number__c = '+7777777777', // no session exists
            sra__Account__c         = testAccount.Id,
            sra__Message_Body__c    = 'Orphan outbound'
        );
        insert outboundMsg;
        Test.stopTest();

        sra__Message_History__c updated = [
            SELECT Id, Message_Session__c FROM sra__Message_History__c WHERE Id = :outboundMsg.Id
        ];
        System.assertEquals(null, updated.Message_Session__c, 'No session to link to');
    }

    // ─────────────────────────────────────────────
    // Test 8: AutoReplyHelper direct method coverage
    // ─────────────────────────────────────────────
    @isTest
    static void testAutoReplyHelperMethods() {
        setupMessageCustomization();
        Account testAccount = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Type__c              = 'Inbound',
            sra__Sender_Number__c     = '+8888888888',
            sra__Receiver_Number__c   = '+0987654321',
            sra__Account__c           = testAccount.Id,
            sra__Message_Body__c      = 'Test',
            sra__Related_Object_Id__c = testAccount.Id
        );
        insert inboundMsg;

        Test.startTest();
        List<Message_Session__c> sessions = [
            SELECT Id, Phone_Number__c, Session_Status__c FROM Message_Session__c
            WHERE Phone_Number__c = '+8888888888'
        ];

        Set<String> phoneNumbers = new Set<String>{ '+8888888888' };
        Map<String, sra__Message_History__c> latestMessages =
            AutoReplyHelper.getLatestInboundMessages(phoneNumbers);

        System.assertEquals(1, latestMessages.size(), 'Should return one latest message');
        System.assert(latestMessages.containsKey('+8888888888'), 'Should contain the phone number key');

        sra__Message_History__c createdMsg = AutoReplyHelper.createOutboundMessage(
            '+8888888888',
            '+0987654321',
            testAccount.Id,
            'Test auto-reply',
            testAccount.Id,
            sessions[0].Id
        );
        System.assertEquals('Outbound', createdMsg.sra__Type__c);
        System.assertEquals('+8888888888', createdMsg.sra__Receiver_Number__c);
        System.assertEquals('Test auto-reply', createdMsg.sra__Message_Body__c);
        System.assertEquals(testAccount.Id, createdMsg.sra__Account__c);
        System.assertEquals(sessions[0].Id, createdMsg.Message_Session__c);

        Test.stopTest();
    }

    // ─────────────────────────────────────────────
    // Test 9: Batch of inbound messages — multiple senders in one trigger fire
    // ─────────────────────────────────────────────
    @isTest
    static void testBatchInboundMessagesDifferentSenders() {
        setupMessageCustomization();
        Account testAccount = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        List<sra__Message_History__c> msgs = new List<sra__Message_History__c>{
            new sra__Message_History__c(
                sra__Type__c            = 'Inbound',
                sra__Sender_Number__c   = '+9991111111',
                sra__Receiver_Number__c = '+0987654321',
                sra__Account__c         = testAccount.Id,
                sra__Message_Body__c    = 'Sender A'
            ),
            new sra__Message_History__c(
                sra__Type__c            = 'Inbound',
                sra__Sender_Number__c   = '+9992222222',
                sra__Receiver_Number__c = '+0987654321',
                sra__Account__c         = testAccount.Id,
                sra__Message_Body__c    = 'Sender B'
            )
        };
        insert msgs;
        Test.stopTest();

        List<Message_Session__c> sessions = [
            SELECT Id FROM Message_Session__c
            WHERE Phone_Number__c IN ('+9991111111', '+9992222222')
        ];
        System.assertEquals(2, sessions.size(), 'Two sessions should be created for two senders');
    }
}