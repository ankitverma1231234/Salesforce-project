trigger AllergyIntoleranceTrigger on AllergyIntolerance (after insert, after update, after delete) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.AllergyIntoleranceTrigger__c) {
        return;
    }
    
    if (Trigger.isAfter && Trigger.isDelete) {RecordAuditLogHandler.logDeletedRecords(Trigger.old,'AllergyIntolerance','AllergyId__c','Account','PatientId');}    
    
    String objectType = 'AllergyIntolerance';
    
    if(Trigger.isDelete) {
        Set<Id> recordIds = new Set<Id>(); 
        for (AllergyIntolerance ai : Trigger.old) {
            recordIds.add(ai.Id);
        }
        
        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(recordIds, 'AllergyIntolerance');
        }
    } else {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>(); 
        String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';
        
        for (AllergyIntolerance ai : Trigger.new) {
            if (ai.PatientId != null) {
                accountIds.add(ai.PatientId);
                changedRecordIds.add(ai.Id); 
            }
        }
        
        if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(accountIds, operation, objectType, changedRecordIds);
        }
    }
}