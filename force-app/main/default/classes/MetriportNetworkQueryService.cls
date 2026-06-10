public without sharing class MetriportNetworkQueryService {

    @AuraEnabled
    public static String initiateNetworkQuery(String metriportPatientId) {
        if (String.isBlank(metriportPatientId)) {
            throw new AuraHandledException('Patient ID is required.');
        }

        Metriport_Config__mdt meta;
        try {
            meta = [
                SELECT API_Key__c, Base_URL__c
                FROM   Metriport_Config__mdt
                WHERE  Active__c = true
                LIMIT  1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Metriport config not found: ' + e.getMessage());
        }

        String apiKey  = meta.API_Key__c;
        String baseUrl = meta.Base_URL__c.removeEnd('/');

        if (String.isBlank(apiKey) || String.isBlank(baseUrl)) {
            throw new AuraHandledException('Metriport_Config__mdt is missing required fields.');
        }

        String endpoint = baseUrl
            + '/medical/v1/network/query'
            + '?patientId=' + EncodingUtil.urlEncode(metriportPatientId, 'UTF-8');

        String requestBodyJson = JSON.serialize(new Map<String, Object>{
            'sources' => new Map<String, Object>{
                'hie'      => new Map<String, Object>{ 'enabled' => true },
                'pharmacy' => new Map<String, Object>{ 'enabled' => true },
                'lab'      => new Map<String, Object>{ 'enabled' => true }
            },
            'metadata' => new Map<String, Object>{
                'source'    => 'Salesforce',
                'patientId' => metriportPatientId
            }
        });

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', apiKey);
        req.setBody(requestBodyJson);
        req.setTimeout(120000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException ce) {
            logError(metriportPatientId, 'CalloutException', ce.getMessage());
            throw new AuraHandledException('Callout failed: ' + ce.getMessage());
        }

        Integer statusCode = res.getStatusCode();
        String  body       = res.getBody();

        if (statusCode == 200 || statusCode == 201 || statusCode == 202) {
            System.debug('✅ Network Query initiated for patient: ' + metriportPatientId);
            return String.isBlank(body) ? '{"status":"accepted"}' : body;
        }

        logError(metriportPatientId, 'HTTP_' + statusCode, body);
        throw new AuraHandledException('Network Query failed (' + statusCode + '): ' + body);
    }
    @AuraEnabled
public static void startMetriportCaseFlow(Id accountId, String metriportPatientId) {

    System.debug('=== startMetriportCaseFlow START ===');

    initiateNetworkQuery(metriportPatientId);

    System.debug('=== About to enqueue Queueable ===');

    MetriportCaseCreationJob.enqueueDelayed(accountId);

    System.debug('=== Queueable enqueued ===');
}
    
   

    private static void logError(String patientId, String statusCode, String message) {
        try {
            Database.insert(new Error_Log__c(
                Object_API_Name__c    = 'Network Query',
                Error_Message__c      = message,
                Record_External_Id__c = patientId,
                Context__c            = 'MetriportNetworkQueryService.initiateNetworkQuery',
                Stack_Trace__c        = 'StatusCode: ' + statusCode + ' | PatientId: ' + patientId
            ), false);
        } catch (Exception ex) {
            System.debug('⚠️ Could not write Error_Log__c: ' + ex.getMessage());
        }
    }
}