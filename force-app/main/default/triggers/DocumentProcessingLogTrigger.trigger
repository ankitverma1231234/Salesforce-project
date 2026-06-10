trigger DocumentProcessingLogTrigger on Document_Processing_Log__c (after update) {
    DocumentProcessingLogTriggerHandler.handle(Trigger.new, Trigger.oldMap);
}