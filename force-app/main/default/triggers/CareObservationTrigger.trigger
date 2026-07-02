trigger CareObservationTrigger on CareObservation (after insert, after update, after delete) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.Care_Observation_Checkbox__c) {
        return;
    }
 
    if (Trigger.isDelete && Trigger.isAfter) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'CareObservation',
            'ObservationId__c',
            'Account',
            'ObservedSubjectId'
        );
        
        Set<Id> recordIds = new Set<Id>(); 
        for(CareObservation co : Trigger.old){
            recordIds.add(co.Id);
        }
        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(
                recordIds, 'CareObservation'
            );
        }
        
        return;
    }
    
    // ── Insert / Update ───────────────────────────────────────────────
    String objectType        = 'CareObservation';
    Set<Id> accountIds       = new Set<Id>();
    Set<Id> changedRecordIds = new Set<Id>();
    String operation         = Trigger.isInsert ? 'INSERT' : 'UPDATE';
    Map<Id, Account> accountsToUpdate = new Map<Id, Account>();
    
    for (CareObservation obs : Trigger.new) {  
        if (obs.ObservedSubjectId == null) continue;
        
        accountIds.add(obs.ObservedSubjectId);
        changedRecordIds.add(obs.Id);
        
        if (String.isBlank(obs.Value_Quantity__c)) continue;
        
        String valueLower = obs.Value_Quantity__c.toLowerCase();
        Decimal numericValue;
        try {
            String numberOnly = obs.Value_Quantity__c.replaceAll('[^0-9\\.]', '');
            numericValue = Decimal.valueOf(numberOnly);
        } catch (Exception e) {
            continue;
        }
        
        Account acc = accountsToUpdate.get(obs.ObservedSubjectId);
        if (acc == null) {
            acc = new Account(Id = obs.ObservedSubjectId);
        }
        
        if (obs.Name == 'Body weight') {
            if (valueLower.contains('kg')) {
                numericValue = numericValue * 2.20462;
            }
            acc.Weight_in_pounds__pc = numericValue.setScale(2);
        } else if (obs.Name == 'Body height') {
            if (valueLower.contains('cm')) {
                numericValue = numericValue * 0.393701;
            }
            acc.Height_in_inches__pc = numericValue.setScale(2);
        }
        
        accountsToUpdate.put(acc.Id, acc);
    }
    
    if (!accountsToUpdate.isEmpty()) {
        update accountsToUpdate.values();
    }
    
    if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
        MedicalSalesforceRecord.sendPatientDataToThirdParty(
            accountIds, operation, objectType, changedRecordIds
        );
    }
}