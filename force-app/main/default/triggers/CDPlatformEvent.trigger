trigger CDPlatformEvent on Content_Document_Event__e (after insert) {
    
    List<Id> docIds = new List<Id>();
    
    for (Content_Document_Event__e evt : Trigger.new) {
        if (evt.ContentDocumentId__c != null) {
            docIds.add((Id)evt.ContentDocumentId__c);
        }
    }
    
    if (!docIds.isEmpty()) {
        System.enqueueJob(new ContentDocumentPrepareQueueable(docIds));
    }
    
}