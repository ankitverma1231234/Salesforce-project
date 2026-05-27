trigger HealthConditionTrigger on HealthCondition (after insert, after update, after delete) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.HealthConditionTrigger__c) {
        return;
    }
    
    String objectType = 'HealthCondition';    
    if(Trigger.isDelete && Trigger.isAfter) {        
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'HealthCondition',   
            'ConditionId__c',           
            'Account',                   
            'PatientId'                  
        ); 
        Set<Id> recordIds = new Set<Id>();        
        for (HealthCondition hc : Trigger.old) {
            recordIds.add(hc.Id);
        }        
        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(recordIds, 'HealthCondition');
        }
    } else {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>(); 
        String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';
        
        for (HealthCondition hc : Trigger.new) {
            if (hc.PatientId != null) {
                accountIds.add(hc.PatientId);
                changedRecordIds.add(hc.Id); 
            }
        }
        
        if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(accountIds, operation, objectType, changedRecordIds);
        }
    }
}