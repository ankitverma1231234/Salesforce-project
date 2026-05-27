trigger HealthcareProfessionalTrigger on HealthcarePractitionerFacility (after insert, after update, after delete) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.HealthcareProfessionalTrigger__c) {
        return;
    }
    String objectType = 'HealthcarePractitionerFacility';
    
       if(Trigger.isDelete &&Trigger.isAfter) {
        //logic for delete log record 
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'HealthcarePractitionerFacility',   
            'PractitionerId__c',    
            'Account',                  
            'AccountId'                  
        );  
    }
    
    if(Trigger.isDelete) {
        Set<Id> recordIds = new Set<Id>();
        
        for (HealthcarePractitionerFacility hp : Trigger.old) {
            recordIds.add(hp.Id);
        }
        
        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(recordIds, 'HealthcarePractitionerFacility');
        }
    } else {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>();
        String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';
        
        for (HealthcarePractitionerFacility hp : Trigger.new) {
            if (hp.AccountId != null) {
                accountIds.add(hp.AccountId);
                changedRecordIds.add(hp.Id); 
            }
        }
        
        if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(accountIds, operation, objectType, changedRecordIds);
        }
    }
}