public class DeleteRecordsQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> recordIds;
    private String recordType;
    private static final Integer BATCH_SIZE = 10;

    public DeleteRecordsQueueable(List<Id> recordIds, String recordType) {
        this.recordIds = recordIds;
        this.recordType = recordType;
    }

    public void execute(QueueableContext context) {
        BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
        if(apiConfig == null || String.isBlank(apiConfig.Delete_API_Key__c)) {
            System.debug(LoggingLevel.ERROR, 'Delete API configuration not found in Custom Setting');
            return;
        }
        String deleteEndpoint = apiConfig.Delete_API_Key__c;

        for(Integer i = 0; i < recordIds.size(); i += BATCH_SIZE) {
            Integer endIndex = Math.min(i + BATCH_SIZE, recordIds.size());
            List<Id> batchIds = new List<Id>();
            for(Integer j = i; j < endIndex; j++) {
                batchIds.add(recordIds[j]);
            }

            try {
                Map<String, Object> payload = MedicalSalesforceDeleteRecord.buildDeletePayload(batchIds, recordType);
                if(payload == null || payload.isEmpty()) {
                    System.debug('No data to delete for batch starting at index ' + i);
                    continue;
                }

                HttpResponse response = MedicalSalesforceDeleteRecord.sendDeleteHttpRequest(deleteEndpoint, payload);
                if(response != null) {
                    System.debug('Delete ' + recordType + ' - Response Code: ' + response.getStatusCode());
                    if(response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                        System.debug('Successfully deleted ' + recordType + ': ' + batchIds.size() + ' records');
                    } else {
                        System.debug(LoggingLevel.ERROR, 'Failed to delete ' + recordType +
                                   '. Status: ' + response.getStatusCode() +
                                   ' Body: ' + response.getBody());
                    }
                }
            } catch(Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Delete error for batch starting at index ' + i + ': ' + ex.getMessage() +
                           '\nStack: ' + ex.getStackTraceString());
            }
        }
    }
}