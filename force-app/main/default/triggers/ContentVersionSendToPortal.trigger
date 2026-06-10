trigger ContentVersionSendToPortal on ContentVersion (after insert, after update) {
    
  if (Trigger.isAfter && Trigger.isInsert) {
        Set<Id> contentDocIds = new Set<Id>();
        for (ContentVersion cv : Trigger.new) {
            if (cv.ContentDocumentId != null) {
                contentDocIds.add(cv.ContentDocumentId);
            }
        }        
        if (contentDocIds.isEmpty()) return;        
        Set<Id> accountIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocIds
            AND LinkedEntityId != null
        ]) {
            if (cdl.LinkedEntityId.getSObjectType() == Account.SObjectType) {
                accountIds.add(cdl.LinkedEntityId);
            }
        }        
        
        //Logic for sync with portal.        
        Set<Id> contentDocumentIds = new Set<Id>();
        Set<Id> deletedFileIds = new Set<Id>();  
        for (ContentVersion newCv : Trigger.new) {        
            if (newCv.Send_File_to_Portal__c == true) {
                contentDocumentIds.add(newCv.ContentDocumentId);
            }
            
        }
        if (!contentDocumentIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(
                new CDPortalPrepareQueueable(
                    new List<Id>(contentDocumentIds)
                )
            );
        }
        
    }
    
    if (Trigger.isAfter && Trigger.isUpdate) {
        //Logic for file comp update.
        Set<Id> contentDocIds = new Set<Id>();
        for (ContentVersion cv : Trigger.new) {
            if (cv.ContentDocumentId != null) {
                contentDocIds.add(cv.ContentDocumentId);
            }
        }        
        if (contentDocIds.isEmpty()) return;        
        Set<Id> accountIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocIds
            AND LinkedEntityId != null
        ]) {
            if (cdl.LinkedEntityId.getSObjectType() == Account.SObjectType) {
                accountIds.add(cdl.LinkedEntityId);
            }
        }        
        
        
        //Logic for sync with portal.        
        Set<Id> contentDocumentIds = new Set<Id>();
        Set<Id> contentDocumentIdsForAITrace = new Set<Id>();
        Set<Id> deletedFileIds = new Set<Id>();  
        for (ContentVersion newCv : Trigger.new) {
            ContentVersion oldCv = Trigger.oldMap.get(newCv.Id);            
            boolean descriptionChange = oldCv.Description != newCv.Description;
            boolean dateChange = oldCv.Service_Date_Time__c != newCv.Service_Date_Time__c;
            boolean titleChange = oldCv.Title != newCv.Title;
            boolean documentTypeChange = oldCv.Document_Type__c != newCv.Document_Type__c;
            boolean sourceTypeChange = oldCv.Source_Type__c != newCv.Source_Type__c;
            boolean categoryChange = oldCv.Category__c != newCv.Category__c;
            boolean wasEnabled = oldCv.Send_File_to_Portal__c == true;
            boolean isEnabled = newCv.Send_File_to_Portal__c == true;
            boolean isStillEnabled = wasEnabled && isEnabled;
            
            if (
                (isEnabled && !wasEnabled)
                ||
                (isStillEnabled && (descriptionChange || dateChange || titleChange || documentTypeChange ||sourceTypeChange ||
                categoryChange))
            ) {
                contentDocumentIds.add(newCv.ContentDocumentId);
            }
            if (!isEnabled && wasEnabled) {
                deletedFileIds.add(newCv.Id);
            }
            if (isEnabled && !wasEnabled){
                contentDocumentIdsForAITrace.add(newCv.ContentDocumentId);
            }
        }
        if (!contentDocumentIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(
                new CDPortalPrepareQueueable(
                    new List<Id>(contentDocumentIds)
                )
            );
        }
                
        if(!contentDocumentIdsForAITrace.isEmpty()){
            system.debug('contentDocumentIdsForAITrace'+contentDocumentIdsForAITrace);
            List<ContentVersion> ConVerForAiFileToPortal = [Select Id,Send_File_to_Portal__c from ContentVersion where Related_File__c in :contentDocumentIdsForAITrace];
            for(ContentVersion cv : ConVerForAiFileToPortal){ 
                cv.Send_File_to_Portal__c = true ; 
            }
            if(!ConVerForAiFileToPortal.isEmpty()){
                system.debug('contentDocumentIdsForAITrace'+contentDocumentIdsForAITrace);
                update ConVerForAiFileToPortal;
            }
        }
        
        if (!deletedFileIds.isEmpty() && !Test.isRunningTest()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(deletedFileIds, 'ContentVersion');
        }
    }     
}