trigger VisitTrigger on Visit (after delete, after insert, after update) {    
    if(Trigger.isDelete &&Trigger.isAfter) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'Visit',   
            'VisitId__c',    
            'Account',                  
            'AccountId'                  
        );  
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        VisitNotificationHandler.handleAfterInsert(Trigger.new);   
    }
    if(Trigger.isAfter && Trigger.isUpdate){
        VisitNotificationHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}