trigger VisitTrigger on Visit (after delete, after insert, after update) {    
    if(Trigger.isDelete &&Trigger.isAfter) {
        //logic for delete log record 
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'Visit',   
            'VisitId__c',    
            'Account',                  
            'AccountId'                  
        );  
    }
    if (Trigger.isAfter &&( Trigger.isInsert || Trigger.isUpdate)) {
        //VisitTiggerHandler.handleAfterInsert(Trigger.new);
    }
}