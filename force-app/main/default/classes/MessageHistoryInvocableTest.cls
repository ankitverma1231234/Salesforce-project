@IsTest
public class MessageHistoryInvocableTest {

    @IsTest
    static void testAppendMessagePrefix_WithExistingMessage() {
        // ---------- Arrange ----------
        // Create custom setting record
        MessageCustomization__c cs = new MessageCustomization__c(
            Name = 'Message',
            Message_Prefix_Body__c = 'PREFIX TEXT'
        );
        insert cs;

        // Create message history record with existing body
        sra__message_history__c msg = new sra__message_history__c(
            sra__message_body__c = 'Original message body'
        );

        List<sra__message_history__c> messages = new List<sra__message_history__c>{ msg };

        // ---------- Act ----------
        Test.startTest();
        MessageHistoryInvocable.appendMessagePrefix(messages);
        Test.stopTest();

        // ---------- Assert ----------
        System.assertEquals(
            'PREFIX TEXT\n\nOriginal message body',
            messages[0].sra__message_body__c,
            'Prefix should be appended before existing message body'
        );
    }

    @IsTest
    static void testAppendMessagePrefix_WithNullMessage() {
        // ---------- Arrange ----------
        // Create custom setting record
        MessageCustomization__c cs = new MessageCustomization__c(
            Name = 'Message',
            Message_Prefix_Body__c = 'ONLY PREFIX'
        );
        insert cs;

        // Create message history record with null body
        sra__message_history__c msg = new sra__message_history__c(
            sra__message_body__c = null
        );

        List<sra__message_history__c> messages = new List<sra__message_history__c>{ msg };

        // ---------- Act ----------
        Test.startTest();
        MessageHistoryInvocable.appendMessagePrefix(messages);
        Test.stopTest();

        // ---------- Assert ----------
        System.assertEquals(
            'ONLY PREFIX',
            messages[0].sra__message_body__c,
            'Message body should be set to prefix when originally null'
        );
    }

    @IsTest
    static void testAppendMessagePrefix_NoCustomSetting() {
        // ---------- Arrange ----------
        // No custom setting created

        sra__message_history__c msg = new sra__message_history__c(
            sra__message_body__c = 'Message without prefix'
        );

        List<sra__message_history__c> messages = new List<sra__message_history__c>{ msg };

        // ---------- Act ----------
        Test.startTest();
        MessageHistoryInvocable.appendMessagePrefix(messages);
        Test.stopTest();

        // ---------- Assert ----------
        System.assertEquals(
            'Message without prefix',
            messages[0].sra__message_body__c,
            'Message body should remain unchanged if no custom setting exists'
        );
    }
}