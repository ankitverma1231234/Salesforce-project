trigger FileStorageAccountEventTrigger on fra__File_Storage__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        FileStorageAccountEventHandler.handleAfterInsert(Trigger.new);
    }
}