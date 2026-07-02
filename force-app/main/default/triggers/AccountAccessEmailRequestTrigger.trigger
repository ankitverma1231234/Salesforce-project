trigger AccountAccessEmailRequestTrigger on Account_Access_Email_Request__e (after insert) {
   List<Account_Head_Relationship__c> toInsert = new List<Account_Head_Relationship__c>();
    
    for (Account_Access_Email_Request__e evt : Trigger.new) {
        
        if (String.isBlank(evt.Payload__c)) continue;
        
        try {
            List<Object> rows = (List<Object>) JSON.deserializeUntyped(evt.Payload__c);
            
            for (Object obj : rows) {
                Map<String, Object> row = (Map<String, Object>) obj;
                
                Account_Head_Relationship__c jr = new Account_Head_Relationship__c(
                    Member_Account__c            = (String) row.get('Member_Account__c'),
                    Authorized_Account_Access__c = (String) row.get('Authorized_Account_Access__c'),
                    Relationship__c              = (String) row.get('Relationship__c'),
                    Portal_Access_Status__c      = (String) row.get('Portal_Access_Status__c'),
                    Give_Access__c               = row.get('Give_Access__c') == true,
                    Request_Access__c            = row.get('Request_Access__c') == true
                );
                toInsert.add(jr);
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'AccountHeadLinkEventTrigger parse error: ' + e.getMessage());
        }
    }
    
    if (!toInsert.isEmpty()) {
        try {
            insert toInsert; // Runs as Automated Process — full permissions ✅
        } catch (DmlException dml) {
            System.debug(LoggingLevel.ERROR,
                'AccountHeadLinkEventTrigger DML error: ' + dml.getMessage());
        }
    }
}