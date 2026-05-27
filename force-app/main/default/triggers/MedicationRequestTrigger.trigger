trigger MedicationRequestTrigger on MedicationRequest  (after delete) {    
    if(Trigger.isDelete &&Trigger.isAfter) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'MedicationRequest',   
            'MedicationRequestId__c',    
            'Account',                  
            'PatientId'                  
        );  
    }
}