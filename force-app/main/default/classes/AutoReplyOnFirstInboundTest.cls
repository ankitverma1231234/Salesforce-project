@isTest(SeeAllData=true)
public class AutoReplyOnFirstInboundTest {

    @isTest
    static void testAutoReplyOnFirstInbound() {

        // 🔹 Get an existing Person Account (DO NOT CREATE)
        Account testAccount = [
            SELECT Id 
            FROM Account 
            WHERE IsPersonAccount = true 
            LIMIT 1
        ];

        System.assertNotEquals(
            null,
            testAccount,
            'Person Account must exist in org'
        );

        // 🔹 Get the required message template
        sra__Message_Template__c templateRec = [
            SELECT Id, sra__Template_Body__c
            FROM sra__Message_Template__c
            WHERE sra__Object_Name__c = 'sra__Message_History__c'
            AND Name = 'autoOutboundMessage'
            LIMIT 1
        ];

        // 🔹 Create FIRST inbound message for the account
        sra__Message_History__c inboundMsg = new sra__Message_History__c(
            sra__Account__c = testAccount.Id,
            sra__Type__c = 'Inbound',
            sra__Sender_Number__c = '+911234567890',
            sra__Receiver_Number__c = '+919876543210',
            sra__Message_Body__c = 'Hello'
        );

        Test.startTest();
        insert inboundMsg;
        Test.stopTest();

        // 🔹 Validate outbound auto-reply was created
        List<sra__Message_History__c> outboundMsgs = [
            SELECT Id, sra__Type__c, sra__Message_Body__c,
                   sra__Sender_Number__c, sra__Receiver_Number__c
            FROM sra__Message_History__c
            WHERE sra__Account__c = :testAccount.Id
            AND sra__Type__c = 'Outbound'
        ];
    }
}