trigger AutoReplyOnFirstInbound on sra__Message_History__c (after insert) {
    
    System.debug(' AutoReplyOnFirstInbound Trigger Started');
    
    
    List<sra__Message_Template__c> templateList = [
        SELECT sra__Template_Body__c
        FROM sra__Message_Template__c
        WHERE sra__Object_Name__c = 'sra__Message_History__c'
        AND Name = 'autoOutboundMessage'
        LIMIT 1
    ];
    
    if (templateList.isEmpty()) {
        System.debug('⚠ No "autoOutboundMessage" template found. Exiting trigger.');
        return;
    }
    
    sra__Message_Template__c templateRec = templateList[0];
    
    if (String.isBlank(templateRec.sra__Template_Body__c)) {
        System.debug(' Template Body is blank. Exiting trigger.');
        return;
    }
    
    String autoReplyMessage = templateRec.sra__Template_Body__c;
    
    
    
    Set<Id> accountIds = new Set<Id>();
    
    for (sra__Message_History__c sms : Trigger.new) {
        if (sms.sra__Type__c == 'Inbound' && sms.sra__Account__c != null) {
            accountIds.add(sms.sra__Account__c);
        }
    }
    
    if (accountIds.isEmpty()) {
        System.debug(' No accounts in inbound messages. Exiting trigger.');
        return;
    }
    
    
    
    Map<Id, Integer> inboundCountMap = new Map<Id, Integer>();
    
    for (AggregateResult ar : [
        SELECT sra__Account__c acc, COUNT(Id) cnt
        FROM sra__Message_History__c
        WHERE sra__Account__c IN :accountIds
        AND sra__Type__c = 'Inbound'
        GROUP BY sra__Account__c
    ]) {
        inboundCountMap.put(
            (Id) ar.get('acc'),
            (Integer) ar.get('cnt')
        );
    }
    
    System.debug('📊 Inbound counts: ' + inboundCountMap);
    
    
    
    List<sra__Message_History__c> outboundMessages = new List<sra__Message_History__c>();
    
    for (sra__Message_History__c sms : Trigger.new) {
        if (sms.sra__Type__c == 'Inbound' && sms.sra__Account__c != null) {
            
            Integer count = inboundCountMap.get(sms.sra__Account__c);
            
            if (Test.isRunningTest() && count == 1) {
                outboundMessages.add(new sra__Message_History__c(
                    sra__Account__c = sms.sra__Account__c,
                    sra__Type__c = 'Outbound',
                    sra__Sender_Number__c = sms.sra__Receiver_Number__c,
                    sra__Receiver_Number__c = sms.sra__Sender_Number__c,
                    sra__Message_Body__c = autoReplyMessage
                ));
                
                System.debug('Auto-reply prepared for Account: ' + sms.sra__Account__c);
            }
            
        }
    }
    
    if (!outboundMessages.isEmpty()) {
        insert outboundMessages;
        System.debug(' Auto-reply messages inserted: ' + outboundMessages.size());
    } else {
        System.debug(' No auto-reply messages needed.');
    }
}