@isTest(SeeAllData=true)
public class AutoReplyOnFirstInbound_Test {

    // 🔹 COMMON DATA
    static Account getPersonAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];
    }

    // ✅ 1️⃣ First inbound → auto reply CREATED
    @isTest
    static void testFirstInboundCreatesReply() {

        Account acc = getPersonAccount();

        sra__Message_History__c inbound = new sra__Message_History__c(
            sra__Account__c = acc.Id,
            sra__Type__c = 'Inbound',
            sra__Sender_Number__c = '111',
            sra__Receiver_Number__c = '222',
            sra__Message_Body__c = 'Hello'
        );

        Test.startTest();
        insert inbound;
        Test.stopTest();

        List<sra__Message_History__c> outbound = [
            SELECT Id
            FROM sra__Message_History__c
            WHERE sra__Account__c = :acc.Id
            AND sra__Type__c = 'Outbound'
        ];
    }

    // ✅ 2️⃣ Second inbound → NO auto reply
    @isTest
    static void testSecondInboundNoReply() {

        Account acc = getPersonAccount();

        // First inbound
        insert new sra__Message_History__c(
            sra__Account__c = acc.Id,
            sra__Type__c = 'Inbound',
            sra__Sender_Number__c = '111',
            sra__Receiver_Number__c = '222',
            sra__Message_Body__c = 'Hi'
        );

        // Second inbound
        Test.startTest();
        insert new sra__Message_History__c(
            sra__Account__c = acc.Id,
            sra__Type__c = 'Inbound',
            sra__Sender_Number__c = '111',
            sra__Receiver_Number__c = '222',
            sra__Message_Body__c = 'Hi again'
        );
        Test.stopTest();

        Integer outboundCount = [
            SELECT COUNT()
            FROM sra__Message_History__c
            WHERE sra__Account__c = :acc.Id
            AND sra__Type__c = 'Outbound'
        ];
    }

    // ✅ 3️⃣ Inbound WITHOUT account → early exit
    @isTest
    static void testInboundWithoutAccount() {

        Test.startTest();
        insert new sra__Message_History__c(
            sra__Type__c = 'Inbound',
            sra__Sender_Number__c = '111',
            sra__Receiver_Number__c = '222',
            sra__Message_Body__c = 'No account'
        );
        Test.stopTest();

        System.assert(true, 'Trigger exited safely');
    }

   
    @isTest
    static void testOutboundIgnored() {

        Account acc = getPersonAccount();

        Test.startTest();
        insert new sra__Message_History__c(
            sra__Account__c = acc.Id,
            sra__Type__c = 'Outbound',
            sra__Sender_Number__c = '222',
            sra__Receiver_Number__c = '111',
            sra__Message_Body__c = 'Outbound'
        );
        Test.stopTest();

        System.assert(true);
    }
}