trigger HealthCareProcedureTrigger on HealthCareProcedure (after insert, after update, after delete) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.HealthCareProcedureTrigger__c) {
        return;
    }
    String objectType = 'HealthCareProcedure';
    
    if(Trigger.isDelete && Trigger.isAfter) {        
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'HealthCareProcedure',   
            'ProcedureId__c',           
            'Account',                   
            'Patient__c'                  
        ); 
        Set<Id> recordIds = new Set<Id>();
        
        for (HealthCareProcedure hcp : Trigger.old) {
            recordIds.add(hcp.Id);
        }
        
        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(recordIds, 'HealthCareProcedure');
        }
    } else {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>(); 
        String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';
        
        for (HealthCareProcedure hcp : Trigger.new) {
            if (hcp.Patient__c != null) {
                accountIds.add(hcp.Patient__c);
                changedRecordIds.add(hcp.Id); 
            }
        }
        
        if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(accountIds, operation, objectType, changedRecordIds);
        }
    }
}