trigger FileStoragePublicUrlTrigger on fra__File_Storage__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
       DocumentProcessingTraceabilityService.linkFileStorageRecords(Trigger.new);
    }
}