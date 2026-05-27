trigger DocFlowDocumentTrigger on Doc_Flow_Document__c (after insert, after update) {
    if (Trigger.isAfter) {
        DocFlowDocumentProcessor.handleAfter(Trigger.new, Trigger.oldMap);
    }
}