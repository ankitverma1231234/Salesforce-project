public class MetriportClinicalSummaryBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {

    /***************
     * Schedulable
     ***************/
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new MetriportClinicalSummaryBatch(), 1);
    }

    /***************
     * Batchable
     ***************/
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Metriport_Patient_Id__c, Ready_to_Sent__c
            FROM Account
            WHERE Metriport_Patient_Id__c != null
            AND Metriport_Patient_Id__c != ''
            AND Ready_to_Sent__c = true
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Metriport_Config__mdt meta = [
            SELECT API_Key__c, Base_URL__c
            FROM Metriport_Config__mdt
            WHERE Active__c = true
            LIMIT 1
        ];

        for (Account acc : scope) {
            try {
                String dateFrom  = String.valueOf(Date.today().addMonths(-12));
                String dateTo    = String.valueOf(Date.today());
                String resources = String.join(new List<String>{
                    'MedicationAdministration',
                    'MedicationRequest',
                    'MedicationDispense',
                    'MedicationStatement'
                }, ',');

                String endpoint = meta.Base_URL__c
                    + '/medical/v1/patient/'
                    + EncodingUtil.urlEncode(acc.Metriport_Patient_Id__c, 'UTF-8')
                    + '/consolidated/query'
                    + '?conversionType=json'
                    + '&resources=' + EncodingUtil.urlEncode(resources, 'UTF-8')
                    + '&dateFrom='  + dateFrom
                    + '&dateTo='    + dateTo;

                System.debug('ClinicalSummary Endpoint => ' + endpoint);

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
                System.debug('ClinicalSummary Response for Patient '
                    + acc.Metriport_Patient_Id__c + ' => ' + res.getBody());

            } catch (Exception e) {
                System.debug('Error in ClinicalSummaryBatch for Account ' + acc.Id
                    + ' | Metriport ID: ' + acc.Metriport_Patient_Id__c
                    + ' | Error: ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('MetriportClinicalSummaryBatch completed.');
    }
}