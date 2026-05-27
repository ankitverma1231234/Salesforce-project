trigger CaseTrigger on Case (after insert, after update, after delete) {
    
    /*BatonPortalAPI__c settings = BatonPortalAPI__c.getOrgDefaults();
    User runningUser = [SELECT Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
    if(settings != null && runningUser.Name == settings.Automated_User_Names__c.trim()){
        return;
    }*/
    
    if (Trigger.isDelete) {
        Set<Id> caseIds = new Set<Id>();
        for (Case c : Trigger.old) {
            if (c.Case_Type__c == 'Portal Messages' && c.AccountId != null) {
                caseIds.add(c.Id);
            }
        }
        if (!caseIds.isEmpty()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(caseIds, 'Case');
        }
        return;
    }
    Set<Id> caseIdsToSync = new Set<Id>();
    Map<Id, String> caseDescriptions = new Map<Id, String>();
    
    String operation = Trigger.isInsert ? 'INSERT' : 'UPDATE';
    
    for (Case c : Trigger.new) {
        
        if (c.AccountId != null || c.Case_Type__c == 'Portal Messages') {
            if (Trigger.isUpdate) {
                Case oldCase = Trigger.oldMap.get(c.Id);
                Boolean caseFieldsChanged = 
                    c.Status != oldCase.Status ||
                    c.Subject != oldCase.Subject ||
                    c.Priority != oldCase.Priority ||
                    c.Origin != oldCase.Origin ||
                    c.Type != oldCase.Type ||
                    c.Reason != oldCase.Reason ||
                    c.SuppliedEmail != oldCase.SuppliedEmail ||
                    c.SuppliedPhone != oldCase.SuppliedPhone ||
                    c.OwnerId != oldCase.OwnerId ||
                    c.ContactId != oldCase.ContactId;
                
                if (caseFieldsChanged) {
                    caseIdsToSync.add(c.Id);
                }
                
                Boolean descriptionAdded = String.isBlank(oldCase.Description) && String.isNotBlank(c.Description);
                Boolean descriptionChanged = String.isNotBlank(oldCase.Description) && 
                    String.isNotBlank(c.Description) && 
                    !oldCase.Description.equals(c.Description);
                
                if (descriptionAdded || descriptionChanged) {
                    if (!CaseSalesforceRecord.isCaseDescriptionJustProcessed(c.Id)) {
                        caseDescriptions.put(c.Id, c.Description);
                    }
                }
            } 
            else if (Trigger.isInsert) {
                caseIdsToSync.add(c.Id);
                if (String.isNotBlank(c.Description)) {
                    caseDescriptions.put(c.Id, c.Description);
                }
            }
        }
        
    }
    
    if (!caseIdsToSync.isEmpty()) {
        CaseSalesforceRecord.createPublicLinksSync(caseIdsToSync);
        CaseSalesforceRecord.sendToThirdPartyFuture(caseIdsToSync, operation, true);
    }
    if (!caseDescriptions.isEmpty()) {
        
        BatonPortalAPI__c config = BatonPortalAPI__c.getOrgDefaults();
        String portalGuestUsername = config != null ? config.UserName__c : null;
        Map<Id, Case> caseMap = new Map<Id, Case>(
            [SELECT Id, CreatedBy.Username
             FROM Case
             WHERE Id IN :caseDescriptions.keySet()]
        );
        
        Map<Id, String> filteredCaseDescriptions = new Map<Id, String>();
        
        for (Id caseId : caseDescriptions.keySet()) {
            
            Case c = caseMap.get(caseId);
            if (portalGuestUsername != null &&
                c.CreatedBy.Username == portalGuestUsername) {
                    continue;
                }
            
            filteredCaseDescriptions.put(caseId, caseDescriptions.get(caseId));
        }
        
        if (!filteredCaseDescriptions.isEmpty()) {
            CaseSalesforceRecord.handleCaseDescriptions(filteredCaseDescriptions);
        }
    }
}