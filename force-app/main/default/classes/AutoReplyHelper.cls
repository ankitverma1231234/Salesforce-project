public class AutoReplyHelper {
    public static void sendAutoReplyForNewSessions(List<Message_Session__c> newSessions){
        if (newSessions == null || newSessions.isEmpty()) {
            return;
        }
        MessageCustomization__c customSetting = MessageCustomization__c.getInstance('Message');
        if(customSetting == null || string.isBlank(customSetting.Session_Message_body__c)){
            System.debug('Session_Message_body__c not configured in MessageCustomization__c');
            return;
        }
        String autoReplyMessage = customSetting.Session_Message_body__c;
        Set<String> phoneNumbers = new Set<String>();
        Map<String, Id> phoneToSessionMap = new Map<String, Id>();
        
        for(Message_Session__c session:newSessions){
            if(String.isNotBlank(session.Phone_Number__c) && session.Id != null){
                phoneNumbers.add(session.Phone_Number__c);
                phoneToSessionMap.put(session.Phone_Number__c, session.Id);
            }
        }
        if(phoneNumbers.IsEmpty()){
            return;
        }
        Map<String, sra__Message_History__c> latestInboundMap = getLatestInboundMessages(phoneNumbers);
        if(latestInboundMap.IsEmpty()){
            System.debug('No inbound messages found for phone numbers');
            return;
        }
        // Create Outbound Message
        List<sra__Message_History__c> outboundMessages  = new List<sra__Message_History__c>();
        for(Message_Session__c session : newSessions){
            if(session.Session_Status__c == 'Open' && String.isNotBlank(session.Phone_Number__c)){
                sra__Message_History__c inboundMsg = latestInboundMap.get(session.Phone_Number__c);
                if(inboundMsg != null){
                    Id sessionId = phoneToSessionMap.get(session.Phone_Number__c);
                    outboundMessages.add(createOutboundMessage(
                        inboundMsg.sra__Sender_Number__c,
                        inboundMsg.sra__Receiver_Number__c,
                        inboundMsg.sra__Account__c,
                        autoReplyMessage,
                        inboundMsg.sra__Related_Object_Id__c,
                        sessionId
                    ));
                }
            }
        }
        if(!outboundMessages.isEmpty()){
            try{
                Insert outboundMessages;
            }Catch(Exception ex){
                System.debug('Error sending auto-reply messages: ' + ex.getMessage());
            }
        }
    } 
    public static Map<String, sra__Message_History__c> getLatestInboundMessages(Set<String> phoneNumbers){
        Map<String, sra__Message_History__c> messageMap = new Map<String, sra__Message_History__c>();
        
        List<sra__Message_History__c> inboundMessages = [SELECT Id, sra__Sender_Number__c, sra__Receiver_Number__c,sra__Related_Object_Id__c, sra__Account__c, CreatedDate
            FROM sra__Message_History__c
            WHERE sra__Sender_Number__c IN :phoneNumbers
            AND sra__Type__c = 'Inbound'
            ORDER BY CreatedDate DESC
            LIMIT 1000];

         for(sra__Message_History__c msg : inboundMessages){
             if(!messageMap.containsKey(msg.sra__Sender_Number__c)){
                messageMap.put(msg.sra__Sender_Number__c, msg);
             }
        }
        return messageMap;
    }
    // Create Outbound message with Message Session link
    Public Static sra__Message_History__c createOutboundMessage(
        String receiverNumber,
        String senderNumber,
        Id accountId,
        String messageBody,
        String relatedObjectId,
        Id sessionId){
        sra__Message_History__c outboundMsg = new sra__Message_History__c(
            sra__Type__c = 'Outbound',
            sra__Sender_Number__c = senderNumber,
            sra__Receiver_Number__c = receiverNumber,
            sra__Message_Body__c = messageBody,
            sra__Delivery_Status__c = 'sent'
        );
        if (String.isNotBlank(relatedObjectId)) {
            outboundMsg.sra__Related_Object_Id__c = relatedObjectId;
        }else{
           outboundMsg.sra__Related_Object_Id__c=sessionId;
        }
        if (accountId != null) {
            outboundMsg.sra__Account__c = accountId;
        }
        if (sessionId != null) {
            outboundMsg.Message_Session__c = sessionId;
        }
        return outboundMsg;
    }
}