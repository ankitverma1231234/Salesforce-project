public With Sharing class MessageCloseSessionHandler {
    public Static void UpdateStatus(List<Message_Session__c> newList, Map<Id,Message_Session__c> oldMap){
        Set<Id> justClosedSessionIds = new Set<Id>();
        for(Message_Session__c session: newList){
            Message_Session__c oldSession = oldMap.get(session.Id);
            if(session.Session_Status__c == 'Closed' && oldSession.Session_Status__c != 'Closed'){
                justClosedSessionIds.add(session.Id);
            }
        }
        
        if(justClosedSessionIds.isEmpty()) return;
        // fetch Custom setting
        MessageCustomization__c customSetting = MessageCustomization__c.getInstance('Message');
        String closeMessageBody;
        if(customSetting != null && String.isNotBlank(customSetting.Session_Close_Message_body__c)){
            closeMessageBody = customSetting.Session_Close_Message_body__c;
        }
        if (String.isBlank(closeMessageBody)) return;
        
        Integer queryLimit = justClosedSessionIds.size();
        Map<Id, sra__Message_History__c> sessionToInboundMsg = new Map<Id, sra__Message_History__c>();
        for(sra__Message_History__c msg: [
            SELECT Id,
            sra__Sender_Number__c,
            sra__Receiver_Number__c,
            sra__Account__c,
            sra__Related_Object_Id__c,
            Message_Session__c
            FROM sra__Message_History__c
            WHERE Message_Session__c IN :justClosedSessionIds
            AND sra__Type__c = 'Inbound'
            ORDER BY CreatedDate DESC LIMIT :queryLimit]){
           
             if(!sessionToInboundMsg.containsKey(msg.Message_Session__c)){
                 sessionToInboundMsg.put(msg.Message_Session__c, msg);   
           }      
       }
        if(sessionToInboundMsg.isEmpty()) return;
        
        List<sra__Message_History__c> outboundMessages =  new List<sra__Message_History__c>();
        for(Id sessionId : justClosedSessionIds){
            if(!sessionToInboundMsg.containsKey(sessionId)) continue;
            sra__Message_History__c inboundMsg = sessionToInboundMsg.get(sessionId);
            
            sra__Message_History__c outboundMsg = new sra__Message_History__c();
            outboundMsg.sra__Sender_Number__c  = inboundMsg.sra__Receiver_Number__c;
            outboundMsg.sra__Receiver_Number__c   = inboundMsg.sra__Sender_Number__c;
            outboundMsg.sra__Account__c           = inboundMsg.sra__Account__c;
            outboundMsg.sra__Message_Body__c      = closeMessageBody;
            outboundMsg.sra__Related_Object_Id__c = sessionId;
            outboundMsg.sra__Type__c              = 'Outbound';
            outboundMsg.sra__Delivery_Status__c   = 'sent';
            outboundMsg.Message_Session__c        = sessionId;
            
            outboundMessages.add(outboundMsg);
        }  
        
        if(!outboundMessages.isEmpty()){
            try{
                insert outboundMessages;
            } catch(DmlException  ex){
                system.debug('Error on inserting: ' +ex.getMessage());
            }
           
        }
    }  
}