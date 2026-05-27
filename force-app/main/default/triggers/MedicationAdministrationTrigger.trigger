trigger MedicationAdministrationTrigger on MedicationAdministration (after delete) {    
    if(Trigger.isDelete &&Trigger.isAfter) {
        //logic for delete log record 
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'MedicationAdministration',   
            'MedicationAdministrationId__c',    
            'Account',                  
            'PatientId'                  
        );  
    }
}