trigger MessageHistoryTriggerr on sra__Message_History__c (after insert, before insert) {
    
    // BEFORE INSERT - Handle outbound message prefix
    if (Trigger.isBefore && Trigger.isInsert) {
        List<sra__Message_History__c> outboundMessages = new List<sra__Message_History__c>();
        for (sra__Message_History__c msg : Trigger.new) {
            if (msg.sra__Type__c == 'Outbound') {
                outboundMessages.add(msg);
            }
        }
        if (!outboundMessages.isEmpty()) {
            MessageHistoryInvocable.appendMessagePrefix(outboundMessages);
        }
    }
    
    // AFTER INSERT - Handle session creation and linking
    if (Trigger.isAfter && Trigger.isInsert) {
        MessageSessionHandler.handleInboundMessages(Trigger.new);
        List<sra__Message_History__c> outboundMessages = new List<sra__Message_History__c>();
        for (sra__Message_History__c msg : Trigger.new) {
            if (msg.sra__Type__c == 'Outbound') {
                outboundMessages.add(msg);
            }
        }
        
        if (!outboundMessages.isEmpty()) {
            MessageSessionHandler.linkOutboundMessagesToSessions(outboundMessages);
        }
    }
}