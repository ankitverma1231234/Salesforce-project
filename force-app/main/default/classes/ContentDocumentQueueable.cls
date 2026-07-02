public class ContentDocumentQueueable
implements Queueable, Database.AllowsCallouts {
    private List<String> payloads;
    public ContentDocumentQueueable(List<String> payloads) {
        this.payloads = payloads;
    }
    public void execute(QueueableContext qc) {
        BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
        if (apiConfig == null || String.isBlank(apiConfig.Api_Key__c)) return;
        for (String body : payloads) {
            try{
                HttpRequest req = new HttpRequest();
                req.setEndpoint(apiConfig.Api_Key__c);
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setTimeout(120000);
                req.setBody(body);
                HttpResponse res = new Http().send(req);
                System.debug('API Status: ' + res.getStatus());
            } catch (System.CalloutException e) {
                System.debug('Callout failed: ' + e.getMessage() + ' | Body: ' + body);
            }
        }
    }
}