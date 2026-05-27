public class MessageHistoryInvocable {
    
    /**
     * Process message history records and append message prefix from custom setting
     * @param messageHistoryList List of sra__message_history__c records to process
     */
    public static void appendMessagePrefix(List<sra__message_history__c> messageHistoryList) {
        try {
            // Retrieve the MessageCustomization custom setting with the 'Message' record
            MessageCustomization__c customSetting = MessageCustomization__c.getInstance('Message');
            
            if (customSetting != null && String.isNotBlank(customSetting.Message_Prefix_Body__c)) {
                String messagePrefix = customSetting.Message_Prefix_Body__c;
                
                // Iterate through the message history records and append the prefix to message body
                for (sra__message_history__c messageRecord : messageHistoryList) {
                    if (messageRecord.sra__message_body__c != null) {
                        // Append prefix to existing message body
                        messageRecord.sra__message_body__c = messagePrefix + '\n\n' + messageRecord.sra__message_body__c;

                    } else {
                        // If message body is null, set it to just the prefix
                        messageRecord.sra__message_body__c = messagePrefix;
                    }
                }
            }
        } catch (Exception ex) {
            System.debug('Error in appendMessagePrefix: ' + ex.getMessage());
            throw new AuraHandledException('Error processing message prefix: ' + ex.getMessage());
        }
    }

}