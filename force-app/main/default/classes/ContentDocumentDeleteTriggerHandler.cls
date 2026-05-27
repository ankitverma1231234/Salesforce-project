public class ContentDocumentDeleteTriggerHandler {    
     public static void afterDelete(List<ContentDocument> oldDocs) {
        Set<Id> contentDocIds = new Set<Id>();
        for (ContentDocument cd : oldDocs) {
            contentDocIds.add(cd.Id);
        }
        if (contentDocIds.isEmpty()) {
            return;
        }
        List<ContentVersion> versionsToUpdate = [
            SELECT Id, Is_Content_Document_Deleted__c
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds];
        for (ContentVersion cv : versionsToUpdate) {
            cv.Is_Content_Document_Deleted__c = true;
        }
        if (!versionsToUpdate.isEmpty()) {
            update versionsToUpdate;
        }
    }  
}