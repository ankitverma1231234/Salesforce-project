trigger HealthcareFacilityTrigger on HealthcareFacility (after insert, after update, after delete) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.HealthcareFacilityTrigger__c) {
        return;
    }

    String objectType = 'HealthcareFacility';
    
     if(Trigger.isDelete &&Trigger.isAfter) {
        //logic for delete log record 
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'HealthcareFacility',   
            'OrganizationId__c',    
            'Account',                  
            'AccountId'                  
        );  
    }
    
    if(Trigger.isDelete) {
        Set<Id> recordIds = new Set<Id>();
        
        for (HealthcareFacility hf : Trigger.old) {
            recordIds.add(hf.Id);
        }
        
        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(recordIds, 'HealthcareFacility');
        }
    } else {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>(); 
        String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';
        
        for (HealthcareFacility hf : Trigger.new) {
            if (hf.AccountId != null) {
                accountIds.add(hf.AccountId);
                changedRecordIds.add(hf.Id);
            }
        }
        
        if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(accountIds, operation, objectType, changedRecordIds);
        }
    }
}