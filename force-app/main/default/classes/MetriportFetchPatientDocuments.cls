public class MetriportFetchPatientDocuments {

    @future(callout=true)
    public static void fetchDocuments(String patientId) {

        if (String.isBlank(patientId)) {
            System.debug('⚠️ fetchDocuments skipped — patientId is blank');
            return;
        }

        try {
            /* -------------------------
               Load API configuration
            -------------------------- */
            Metriport_Config__mdt meta;

            try {
                meta = [
                    SELECT API_Key__c, Base_URL__c
                    FROM Metriport_Config__mdt
                    WHERE Active__c = true
                    LIMIT 1
                ];
            } catch (Exception ex) {
                System.debug('❌ No active Metriport_Config__mdt found');
                return;
            }

            if (meta == null ||
                String.isBlank(meta.API_Key__c) ||
                String.isBlank(meta.Base_URL__c)) {

                System.debug('❌ Invalid Metriport configuration — missing API key or Base URL');
                return;
            }

            String apiKey = meta.API_Key__c;
            String baseUrl = meta.Base_URL__c;

            /* -------------------------
               Build endpoint
            -------------------------- */
            String endpointUrl =
                baseUrl +
                '/medical/v1/document?patientId=' +
                EncodingUtil.urlEncode(patientId, 'UTF-8');

            System.debug('Metriport List Documents Endpoint => ' + endpointUrl);

            /* -------------------------
               HTTP Callout
            -------------------------- */
            Http http = new Http();
            HttpRequest req = new HttpRequest();

            req.setEndpoint(endpointUrl);
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', apiKey);
            req.setTimeout(120000); // 120s for large payloads

            HttpResponse res;
            try {
                res = http.send(req);
            } catch (CalloutException ce) {
                System.debug('❌ HTTP callout failed: ' + ce.getMessage());
                return;
            }

            /* -------------------------
               Handle Response
            -------------------------- */
            if (res != null && res.getStatusCode() == 200) {

                String responseBody = res.getBody();
                if (String.isBlank(responseBody)) {
                    System.debug('⚠️ Empty document response from Metriport');
                    return;
                }

                System.debug('Metriport Documents JSON => ' + responseBody);

                // 🔹 Pass JSON to parser / processor class
                MetriportDocumentParser.processDocuments(responseBody, patientId);

            } else {
                System.debug(
                    '❌ Metriport Document List Error | Status: ' +
                    ( res.getStatusCode()+ 'NO RESPONSE') +
                    ' | Body: ' +
                    (res != null ? res.getBody() : 'NULL')
                );
            }

        } catch (Exception e) {
            System.debug('❌ Error in fetchDocuments => ' + e.getMessage());
        }
    }
}