@RestResource(urlMapping='/Metriport/Filtered/Data/*')
global with sharing class MetriportFilteredData {

   @HttpPost
    global static void handleWebhook() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        try {
            String jsonBody = req.requestBody.toString();

            if (String.isBlank(jsonBody)) {
                res.statusCode = 400;
                return;
            }

            if (!Test.isRunningTest()) {
                Database.executeBatch(new MetriportfilterBatch(jsonBody), 1);
            }

            res.statusCode = 200;

        } catch (Exception e) {
            res.statusCode = 500;
            System.debug('❌ Error in webhook: ' + e.getMessage());
        }
    }
}