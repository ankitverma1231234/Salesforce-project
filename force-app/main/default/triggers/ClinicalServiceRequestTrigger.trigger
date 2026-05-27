trigger ClinicalServiceRequestTrigger on ClinicalServiceRequest  (after delete) {    
    if(Trigger.isDelete &&Trigger.isAfter) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'ClinicalServiceRequest',   
            'Service_Request_Id__c',    
            'Account',                  
            'PatientId'                  
        );  
    }
}