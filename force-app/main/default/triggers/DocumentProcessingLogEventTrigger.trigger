trigger DocumentProcessingLogEventTrigger on Document_Processing_Log_Event__e (after insert) {
    List<Document_Processing_Log__c> logs = new List<Document_Processing_Log__c>();

    for (Document_Processing_Log_Event__e eventRecord : Trigger.new) {
        if (String.isBlank(eventRecord.Content_Version_Id__c)) continue;

        logs.add(new Document_Processing_Log__c(
            Content_Version_Id__c = eventRecord.Content_Version_Id__c,
            Is_Active__c = eventRecord.Is_Active__c,
            Ready_for_Attachment__c = eventRecord.Ready_for_Attachment__c
        ));
    }

    if (!logs.isEmpty()) {
        insert logs;
    }
}