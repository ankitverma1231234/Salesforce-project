trigger ContactDuplicateTrigger on Contact (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate) {
           //ContactTriggerHandler.handleAfterInsertUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}