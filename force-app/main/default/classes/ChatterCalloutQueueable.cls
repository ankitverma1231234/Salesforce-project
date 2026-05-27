public class ChatterCalloutQueueable implements Queueable, Database.AllowsCallouts {
    private Id feedItemId;
    private String operation;
    
    public ChatterCalloutQueueable(Id feedItemId, String operation) {
        this.feedItemId = feedItemId;
        this.operation = operation;
    }
    
    public void execute(QueueableContext context) {
        Map<String, Object> chatterData = CaseSalesforceRecord.buildChatterPayload(feedItemId);
        if (chatterData != null && !chatterData.isEmpty()) {
            // reuse the private helpers by making them @TestVisible or public
            HttpRequest req = new HttpRequest();
            BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
            if (apiConfig == null || String.isBlank(apiConfig.CaseKey__c)) return;
            
            req.setEndpoint(apiConfig.CaseKey__c);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            req.setBody(JSON.serialize(chatterData));
            HttpResponse response = new Http().send(req);
            System.debug('Chatter Queueable Response: ' + response.getStatusCode());
        }
    }
}