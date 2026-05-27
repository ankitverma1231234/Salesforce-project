public class MetripointfetchPateintDetails {
    

    @future(callout=true)
    public static void startConsolidatedQuery(String patientId) {
        try {
        Metriport_Config__mdt meta = [SELECT API_Key__c, Base_URL__c FROM Metriport_Config__mdt Where Active__c = true LIMIT 1];
        String apiKey = meta.API_Key__c;
        String baseUrl = meta.Base_URL__c;
            
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            
             String endpointUrl =
                baseUrl +
                '/medical/v1/patient/' +
                EncodingUtil.urlEncode(patientId, 'UTF-8') +
                '/consolidated/query?conversionType=json';

            System.debug('FINAL ENDPOINT URL: ' + endpointUrl);
            System.debug(patientId);
            
            req.setEndpoint(endpointUrl);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', apiKey);

             req.setBody('{}');

            HttpResponse res = http.send(req);

            System.debug('Metriport Start Query Response => ' + res.getBody());
        } catch (Exception e) {
            System.debug('Error in startConsolidatedQuery => ' + e.getMessage());
        }
    }
    
   @future(callout=true)
    public static void startClinicalSummaryQuery(String patientId) {
        try {
            Metriport_Config__mdt meta = [
                SELECT API_Key__c, Base_URL__c
                FROM Metriport_Config__mdt
                WHERE Active__c = true
                LIMIT 1
            ];

            String dateFrom = String.valueOf(Date.today().addMonths(-12));
            String dateTo   = String.valueOf(Date.today());

            String resources = String.join(new List<String>{
                'MedicationAdministration',
                'MedicationRequest',
                'MedicationDispense',
                'MedicationStatement'
            }, ',');
         String endpoint =
                meta.Base_URL__c +
                '/medical/v1/patient/' +
                EncodingUtil.urlEncode(patientId, 'UTF-8') +
                '/consolidated/query' +
                '?conversionType=json' +
                '&resources=' + EncodingUtil.urlEncode(resources, 'UTF-8') +
                '&dateFrom='  + dateFrom +
                '&dateTo='    + dateTo;

            System.debug('ClinicalSummary Endpoint => ' + endpoint);

            // ── Metadata tag (for webhook routing) ────────────────────────
            String body = JSON.serialize(new Map<String, Object>{
                'metadata' => new Map<String, String>{
                    'queryType' => 'Filtered_Data'
                }
            });

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-api-key', meta.API_Key__c);
            req.setBody(body);

            HttpResponse res = new Http().send(req);
            System.debug('ClinicalSummary Query Response => ' + res.getBody());

        } catch (Exception e) {
            System.debug('Error in startClinicalSummaryQuery => ' + e.getMessage());
        }
    }
}