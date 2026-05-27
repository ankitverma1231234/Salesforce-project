@RestResource(urlMapping='/api/metriport/webhook/*')
global class MetriportHandler {
    
    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            String jsonBody = req.requestBody.toString();
                  
            if (!Test.isRunningTest()) {Database.executeBatch(new MetriportPayloadBatch(jsonBody), 1);}
				//System.enqueueJob(new ObservationJob(jsonBody));
            res.statusCode = 200;
            //System.debug('✅ Batch job started');
            
        } catch (Exception e) {
            res.statusCode = 500;
            System.debug('❌ Error in webhook: ' + e.getMessage());
        }
    }
}