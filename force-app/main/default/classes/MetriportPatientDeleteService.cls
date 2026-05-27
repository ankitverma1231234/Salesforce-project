public with sharing class MetriportPatientDeleteService {

    @future(callout=true)
    public static void deleteMetriportPatients(Map<Id, String> accountIdToMetriportPatientId) {
        if (accountIdToMetriportPatientId.isEmpty()) return;

        // Load metadata
        Metriport_Config__mdt meta = [
            SELECT API_Key__c, Base_URL__c, facilityId__c
            FROM Metriport_Config__mdt
            WHERE Active__c = true
            LIMIT 1
        ];
        String apiKey = meta.API_Key__c;
        String baseUrl = meta.Base_URL__c;
        String facilityId = meta.facilityId__c;

        for (Id accountId : accountIdToMetriportPatientId.keySet()) {
            String metriportPatientId = accountIdToMetriportPatientId.get(accountId);

            if (String.isBlank(metriportPatientId)) {
                System.debug('Skipping Account ' + accountId + ': no Metriport Patient ID found.');
                continue;
            }

            try {
                String endpoint = baseUrl + '/medical/v1/patient/' 
                    + EncodingUtil.urlEncode(metriportPatientId, 'UTF-8') 
                    + '?facilityId=' + EncodingUtil.urlEncode(facilityId, 'UTF-8');

                Http http = new Http();
                HttpRequest request = new HttpRequest();
                request.setEndpoint(endpoint);
                request.setMethod('DELETE');
                request.setHeader('x-api-key', apiKey);

                HttpResponse response = http.send(request);

                if (response.getStatusCode() == 204) {
                    System.debug('Metriport Patient deleted successfully. Patient ID: ' + metriportPatientId);
                } else {
                    System.debug('Metriport delete error for Patient ID ' + metriportPatientId 
                        + ': Status=' + response.getStatusCode() 
                        + ' Body=' + response.getBody());
                }

            } catch (Exception ex) {
                System.debug('Exception while deleting Metriport Patient ' + metriportPatientId 
                    + ': ' + ex.getMessage());
            }
        }
    }
}