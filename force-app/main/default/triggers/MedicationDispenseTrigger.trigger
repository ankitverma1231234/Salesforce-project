trigger MedicationDispenseTrigger on MedicationDispense  (after delete) {    
    if(Trigger.isDelete &&Trigger.isAfter) {
        //logic for delete log record 
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'MedicationDispense',   
            'MedicationDispenseId__c',    
            'Account',                  
            'PatientId'                  
        );  
    }
}