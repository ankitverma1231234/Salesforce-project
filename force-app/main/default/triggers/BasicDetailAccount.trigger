trigger BasicDetailAccount on Account (after update, after delete) {
    
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.Account__c) {
        return;
    }
   
    if (Trigger.isUpdate) {
        String objectType = 'Account';
        Set<Id> accountIds = new Set<Id>();
        Set<Id> changedRecordIds = new Set<Id>(); 
        String operation = 'UPDATE';
        
        for (Account ac : Trigger.new) {
            Account oldAc = Trigger.oldMap.get(ac.Id);
            if (ac.Send_Member_to_portal__c != true) {
                continue;
            }
            Boolean heightChanged = (ac.Height_in_inches__pc != null || oldAc.Height_in_inches__pc != null)
                                    && ac.Height_in_inches__pc != oldAc.Height_in_inches__pc;
            Boolean weightChanged = (ac.Weight_in_pounds__pc != null || oldAc.Weight_in_pounds__pc != null)
                                    && ac.Weight_in_pounds__pc != oldAc.Weight_in_pounds__pc;
            String newSummary = ac.Patient_Summary__c != null ? ac.Patient_Summary__c.trim() : '';
            String oldSummary = oldAc.Patient_Summary__c != null ? oldAc.Patient_Summary__c.trim() : '';
            Boolean summaryChanged = newSummary != oldSummary;
            if (heightChanged || weightChanged || summaryChanged) {
                accountIds.add(ac.Id);
                changedRecordIds.add(ac.Id);
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
   
    if (Trigger.isDelete) {
        Set<Id> deleteAccountIds = new Set<Id>();
        
        for (Account ac : Trigger.old) {
            deleteAccountIds.add(ac.Id); 
        }
        
        if (!deleteAccountIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(
                deleteAccountIds, 
                'Account'
            );
        }
    }
}