trigger MemberMediTrigger on MemberPlan (after insert, after update, after delete) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.MemberMediTrigger__c) {
        return;
    }
    String objectType = 'MemberPlan';    
    if(Trigger.isDelete &&Trigger.isAfter) {
        RecordAuditLogHandler.logDeletedRecords(
            Trigger.old,
            'MemberPlan',   
            'CoverageId__c',    
            'Account',                  
            'MemberId'                  
        );  
     Set<Id> recordIds = new Set<Id>();        
        for (MemberPlan mp : Trigger.old) {
            recordIds.add(mp.Id);
        }        
        if (!recordIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(
                recordIds,
                objectType
            );
        }
    }
    else {
        // Handle both INSERT and UPDATE operations
        Set<Id> accountIds = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>();
        String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';
        
        for (MemberPlan mp : Trigger.new) {
            if (mp.MemberId != null) {
                accountIds.add(mp.MemberId);
                changedRecordIds.add(mp.Id); 
            }
        }        
        if (!accountIds.isEmpty() && !changedRecordIds.isEmpty()) {
            MedicalSalesforceRecord.sendPatientDataToThirdParty(
                accountIds,
                operation,
                objectType,
                changedRecordIds
            );
        }
    }
}