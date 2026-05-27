trigger MedicationStatementTrigger on MedicationStatement (after insert, after update, after delete) {
     TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.MedicationStatementTrigger__c) {
        return;
    }
        
    String objectType = 'MedicationStatement';    
    if(Trigger.isDelete &&Trigger.isAfter) {
        //logic for delete log record 
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'MedicationStatement',    
            'MedicationStatementId__c',           
            'Account',                  
            'PatientId' 
        );        
        //Another Logic        
        Set<Id> recordIds = new Set<Id>();        
        for (MedicationStatement ms : Trigger.old) {
            recordIds.add(ms.Id);
        }        
        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(recordIds, 'MedicationStatement');
        }
    } else {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>(); 
        String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';        
        for (MedicationStatement ms : Trigger.new) {
            if (ms.PatientId != null) {
                accountIds.add(ms.PatientId);
                changedRecordIds.add(ms.Id); 
            }
        }        
        if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(accountIds, operation, objectType, changedRecordIds);
        }
    }

}