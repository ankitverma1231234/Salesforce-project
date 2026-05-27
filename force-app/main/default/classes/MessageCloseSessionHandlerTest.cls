@IsTest
public class MessageCloseSessionHandlerTest {

    @TestSetup
    static void setupData() {
        // Custom Setting with close message body
        MessageCustomization__c customSetting = new MessageCustomization__c(
            Name = 'Message',
            Session_Close_Message_body__c = 'Your session has been closed.'
        );
        insert customSetting;

        // Open session
        Message_Session__c session = new Message_Session__c(
            Session_Status__c = 'Open',
            Phone_Number__c   = '1234567890'
        );
        insert session;

        // Inbound message linked to session
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Sender_Number__c   = '1234567890',
            sra__Receiver_Number__c = '0987654321',
            sra__Type__c            = 'Inbound',
            sra__Delivery_Status__c = 'Delivered',
            Message_Session__c      = session.Id
        );
        insert inboundMsg;
    }

    // ─── Test 1: Status Not Changed to Closed — No Outbound Created ───────────
    @IsTest
    static void testNoStatusChange() {
        Message_Session__c session = [
            SELECT Id, Session_Status__c FROM Message_Session__c LIMIT 1];

        // Update something else — not the status
        session.Phone_Number__c = '1111111111';

        Test.startTest();
        update session;
        Test.stopTest();

        List<sra__Message_History__c> outboundMsgs = [
            SELECT Id FROM sra__Message_History__c
            WHERE Message_Session__c = :session.Id
            AND sra__Type__c = 'Outbound'
        ];
        System.assertEquals(
            0,
            outboundMsgs.size(),
            'No outbound message should be created when status is not changed.'
        );
    }

    // ─── Test 2: Status Was Already Closed — No Outbound Created ──────────────
    @IsTest
    static void testAlreadyClosedNoOutbound() {
        Message_Session__c session = [
            SELECT Id FROM Message_Session__c LIMIT 1
        ];

        // First close — this fires the trigger legitimately
        session.Session_Status__c = 'Closed';
        update session;

        // Clear outbound messages from first close
        delete [
            SELECT Id FROM sra__Message_History__c
            WHERE Message_Session__c = :session.Id
            AND sra__Type__c = 'Outbound'
        ];

        // Second update — already Closed → trigger should skip
        session.Phone_Number__c = '0000000000';

        Test.startTest();
        update session;
        Test.stopTest();

        List<sra__Message_History__c> outboundMsgs = [
            SELECT Id FROM sra__Message_History__c
            WHERE Message_Session__c = :session.Id
            AND sra__Type__c = 'Outbound'
        ];
        System.assertEquals(
            0,
            outboundMsgs.size(),
            'No outbound message should be created when session was already Closed.'
        );
    }

    // ─── Test 3: Successful Close — Outbound Message Created ──────────────────
    @IsTest
    static void testSuccessfulCloseCreatesOutbound() {
        Message_Session__c session = [
            SELECT Id FROM Message_Session__c LIMIT 1
        ];

        Test.startTest();
        session.Session_Status__c = 'Closed';
        update session;
        Test.stopTest();

        // Verify outbound message created
        List<sra__Message_History__c> outboundMsgs = [
            SELECT Id,
                   sra__Type__c,
                   sra__Message_Body__c,
                   sra__Sender_Number__c,
                   sra__Receiver_Number__c,
                   sra__Delivery_Status__c
            FROM sra__Message_History__c
            WHERE Message_Session__c = :session.Id
            AND   sra__Type__c = 'Outbound'
        ];

        System.assertEquals(
            1,
            outboundMsgs.size(),
            'Exactly one outbound message should be created.'
        );
        System.assertEquals(
            'Your session has been closed.',
            outboundMsgs[0].sra__Message_Body__c,
            'Outbound message body should match custom setting.'
        );
        System.assertEquals(
            'sent',
            outboundMsgs[0].sra__Delivery_Status__c,
            'Delivery status should be sent.'
        );
        System.assertEquals(
            '0987654321',
            outboundMsgs[0].sra__Sender_Number__c,
            'Sender should be the original receiver number.'
        );
        System.assertEquals(
            '1234567890',
            outboundMsgs[0].sra__Receiver_Number__c,
            'Receiver should be the original sender number.'
        );
    }

    // ─── Test 4: No Custom Setting Body — No Outbound Created ─────────────────
    @IsTest
    static void testBlankCustomSettingBodyNoOutbound() {
        MessageCustomization__c customSetting =
            MessageCustomization__c.getInstance('Message');
        customSetting.Session_Close_Message_body__c = null;
        update customSetting;

        Message_Session__c session = [
            SELECT Id FROM Message_Session__c LIMIT 1
        ];

        Test.startTest();
        session.Session_Status__c = 'Closed';
        update session;
        Test.stopTest();

        List<sra__Message_History__c> outboundMsgs = [
            SELECT Id FROM sra__Message_History__c
            WHERE Message_Session__c = :session.Id
            AND   sra__Type__c = 'Outbound'
        ];
        System.assertEquals(
            0,
            outboundMsgs.size(),
            'No outbound message should be created when close message body is blank.'
        );
    }

    // ─── Test 5: No Inbound Message Exists — No Outbound Created ──────────────
    @IsTest
    static void testNoInboundMessageNoOutbound() {
        // Fresh session with no inbound messages
        Message_Session__c freshSession = new Message_Session__c(
            Session_Status__c = 'Open',
            Phone_Number__c   = '9999999999'
        );
        insert freshSession;

        Test.startTest();
        freshSession.Session_Status__c = 'Closed';
        update freshSession;
        Test.stopTest();

        List<sra__Message_History__c> outboundMsgs = [
            SELECT Id FROM sra__Message_History__c
            WHERE Message_Session__c = :freshSession.Id
            AND   sra__Type__c = 'Outbound'
        ];
        System.assertEquals(
            0,
            outboundMsgs.size(),
            'No outbound message should be created when no inbound message exists.'
        );
    }

    // ─── Test 6: Bulk — Multiple Sessions Closed Together ─────────────────────
    @IsTest
    static void testBulkSessionClose() {
        List<Message_Session__c> sessions = new List<Message_Session__c>();
        for (Integer i = 0; i < 10; i++) {
            sessions.add(new Message_Session__c(
                Session_Status__c = 'Open',
                Phone_Number__c   = '123456789' + i
            ));
        }
        insert sessions;

        List<sra__Message_History__c> inboundMsgs = new List<sra__Message_History__c>();
        for (Message_Session__c s : sessions) {
            inboundMsgs.add(new sra__Message_History__c(
                sra__Sender_Number__c   = s.Phone_Number__c,
                sra__Receiver_Number__c = '0987654321',
                sra__Type__c            = 'Inbound',
                sra__Delivery_Status__c = 'Delivered',
                Message_Session__c      = s.Id
            ));
        }
        insert inboundMsgs;

        for (Message_Session__c s : sessions) {
            s.Session_Status__c = 'Closed';
        }

        Test.startTest();
        update sessions;
        Test.stopTest();

        Set<Id> sessionIds = new Map<Id, Message_Session__c>(sessions).keySet();

        List<sra__Message_History__c> outboundMsgs = [
            SELECT Id FROM sra__Message_History__c
            WHERE Message_Session__c IN :sessionIds
            AND   sra__Type__c = 'Outbound'
        ];
    }
}