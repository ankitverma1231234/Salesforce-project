trigger FamilyMemberHistoryTrigger on Family_Member_History__c(after delete) {    
    if(Trigger.isDelete &&Trigger.isAfter) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'Family_Member_History__c',   
            'FamilyMemberHistoryId__c',    
            'Account',                  
            'Patient__c'                  
        );  
    }
}