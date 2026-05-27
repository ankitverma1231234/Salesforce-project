public class MetriportDailyConsolidatedQueryBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {

    /***************
     * Schedulable
     ***************/
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new MetriportDailyConsolidatedQueryBatch(), 1);
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
        // Load metadata once per batch chunk
        Metriport_Config__mdt meta = [
            SELECT API_Key__c, Base_URL__c
            FROM Metriport_Config__mdt
            WHERE Active__c = true
            LIMIT 1
        ];
        String apiKey = meta.API_Key__c;
        String baseUrl = meta.Base_URL__c;
    
        List<Account> accountsToUpdate = new List<Account>();
    
        for (Account acc : scope) {
            try {
                String endpointUrl = baseUrl
                    + '/medical/v1/patient/'
                    + EncodingUtil.urlEncode(acc.Metriport_Patient_Id__c, 'UTF-8')
                    + '/consolidated/query?conversionType=json';
    
                Http http = new Http();
                HttpRequest req = new HttpRequest();
                req.setEndpoint(endpointUrl);
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('x-api-key', apiKey);
                req.setBody('{}');
    
                HttpResponse res = http.send(req);
    
                System.debug('Metriport Consolidated Query Response for Patient '
                    + acc.Metriport_Patient_Id__c + ' => ' + res.getBody());
    
                // ✅ Only update if callout succeeds
                acc.Last_Refresh_Date__c = System.now();
                accountsToUpdate.add(acc);
    
            } catch (Exception ex) {
                System.debug('Error triggering consolidated query for Account ' + acc.Id
                    + ' | Metriport ID: ' + acc.Metriport_Patient_Id__c
                    + ' | Error: ' + ex.getMessage());
            }
        }
    
        // ✅ Bulk update (important!)
        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('MetriportDailyConsolidatedQueryBatch completed.');
    }
}