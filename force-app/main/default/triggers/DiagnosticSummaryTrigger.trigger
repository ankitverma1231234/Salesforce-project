trigger DiagnosticSummaryTrigger on DiagnosticSummary(after delete) {    
    if(Trigger.isDelete &&Trigger.isAfter) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'DiagnosticSummary',   
            'DiagnosticReportId__c',    
            'Account',                  
            'PatientId'                  
        );  
    }
}