trigger ContentDocumentDeleteTrigger on ContentDocument (before delete) {    
    Set<Id> contentDocumentIds = new Set<Id>();
    
    for (ContentDocument doc : Trigger.old) {
        contentDocumentIds.add(doc.Id);
    }
    System.debug('contentDocumentIds>>>> ' + contentDocumentIds);
    
    Set<Id> deletedFileIds = new Set<Id>();
    List<Deleted_Record_Audit__c> auditRecords = new List<Deleted_Record_Audit__c>();
    
    for (ContentVersion cv : [
        SELECT Id, ContentDocumentId, FirstPublishLocationId, Title, Send_File_to_Portal__c
        FROM ContentVersion
        WHERE ContentDocumentId IN :contentDocumentIds
        AND IsLatest = true
        AND FirstPublishLocationId != null
    ]) {
        if (String.valueOf(cv.FirstPublishLocationId).startsWith('001')) {
            // Existing portal delete logic
            if (cv.Send_File_to_Portal__c == true) {
                deletedFileIds.add(cv.Id);
            }
            
            // 🔎 Audit record for Medical Summary deletion
            if (cv.Title == 'Medical Summary') {
                Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c();
                audit.Object_API_Name__c = 'ContentVersion';
                audit.External_Id_Metriport__c = 'Medical Summary';
                audit.Parent_Record_Id__c = cv.FirstPublishLocationId;
                auditRecords.add(audit);
            }
        }
    }
    
    System.debug('deletedFileIds>>>> ' + deletedFileIds);
    System.debug('auditRecords>>>> ' + auditRecords);
    
    if (!deletedFileIds.isEmpty()) {
        MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(
            deletedFileIds,
            'ContentVersion'
        );
    }
    
    if (!auditRecords.isEmpty()) {
        insert auditRecords;
    }
}