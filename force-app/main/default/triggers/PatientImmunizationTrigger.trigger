trigger PatientImmunizationTrigger on PatientImmunization   (after delete) {    
    if(Trigger.isDelete &&Trigger.isAfter) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'PatientImmunization',   
            'ImmunizationId__c',    
            'Account',                  
            'PatientId'                  
        );  
    }
}