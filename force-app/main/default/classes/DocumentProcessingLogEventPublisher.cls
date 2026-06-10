public with sharing class DocumentProcessingLogEventPublisher {

    public static void publishInitialLog(Id contentVersionId) {
        if (contentVersionId == null) return;

        Document_Processing_Log_Event__e eventRecord =
            new Document_Processing_Log_Event__e(
                Content_Version_Id__c = String.valueOf(contentVersionId),
                Is_Active__c = true,
                Ready_for_Attachment__c = true
            );

        Database.SaveResult result = EventBus.publish(eventRecord);
        if (!result.isSuccess()) {
            System.debug(
                LoggingLevel.ERROR,
                'Failed to publish Document_Processing_Log_Event__e: ' +
                result.getErrors()[0].getMessage()
            );
        }
    }
}