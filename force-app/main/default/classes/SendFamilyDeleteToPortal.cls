public class SendFamilyDeleteToPortal {
    
    @future(callout=true)
    public static void sendFamilyDeleteFuture(Id parentAccountId, Id deletedChildAccountId, Id ahrId) {
        processFamilyDeleteSync(parentAccountId, deletedChildAccountId, ahrId);
    }
    
    public static void processFamilyDeleteSync(Id parentAccountId, Id deletedChildAccountId, Id ahrId) {
        BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
        if (apiConfig == null || String.isBlank(apiConfig.Api_key_2__c)) {
            System.debug(LoggingLevel.ERROR, 'Api_key_2__c not configured');
            return;
        }
        String deleteEndpoint = apiConfig.Api_key_2__c;

        List<Account> parentAccounts = [
            SELECT Id, FirstName, LastName, Name, PersonContactId, Family_Head__c
            FROM Account
            WHERE Id = :parentAccountId
            LIMIT 1
        ];
        if (parentAccounts.isEmpty()) return;
        Account headAccount = parentAccounts[0];

        List<Account> deletedChildAccounts = [
            SELECT Id, Name, FirstName, LastName, PersonContactId
            FROM Account
            WHERE Id = :deletedChildAccountId
            LIMIT 1
        ];
        if (deletedChildAccounts.isEmpty()) return;
        Account deletedChild = deletedChildAccounts[0];

        Map<String, Object> parentMap = new Map<String, Object>();
        parentMap.put('accountId',  String.valueOf(headAccount.Id));
        parentMap.put('first_name', headAccount.FirstName != null ? headAccount.FirstName : '');
        parentMap.put('last_name',  headAccount.LastName  != null ? headAccount.LastName  : '');
        parentMap.put('id',         headAccount.PersonContactId != null ? String.valueOf(headAccount.PersonContactId) : null);
        parentMap.put('is_head',    headAccount.Family_Head__c);

        Map<String, Object> childMap = new Map<String, Object>();
        childMap.put('accountId',                  String.valueOf(deletedChild.Id));
        childMap.put('name',                       deletedChild.Name != null ? deletedChild.Name : '');
        childMap.put('id',                         deletedChild.PersonContactId != null ? String.valueOf(deletedChild.PersonContactId) : null);
        childMap.put('headAccountName',            headAccount.Name != null ? headAccount.Name : '');
        childMap.put('is_delete',                  true);
        childMap.put('account_headrelationshipid', ahrId != null ? String.valueOf(ahrId) : null);

        Map<String, Object> payload = new Map<String, Object>();
        payload.put('contactId', headAccount.PersonContactId != null ? String.valueOf(headAccount.PersonContactId) : null);
        payload.put('parent',    parentMap);
        payload.put('children',  new List<Map<String, Object>>{ childMap });

        try {
            HttpResponse res = sendHttpRequest(deleteEndpoint, payload);
            if (res != null) {
                if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    System.debug('Family delete sent - Parent: ' + parentAccountId + ' Child: ' + deletedChildAccountId + ' AHR: ' + ahrId);
                } else {
                    System.debug(LoggingLevel.ERROR, 'Family delete failed: ' + res.getStatusCode() + ' ' + res.getBody());
                    System.debug(LoggingLevel.ERROR, 'Request Body: ' + JSON.serialize(payload));
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Family delete callout error: ' + ex.getMessage());
        }
    }
    
    private static HttpResponse sendHttpRequest(String endpoint, Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(payload));
        System.debug('Request Body: ' + JSON.serialize(payload));
        return new Http().send(req);
    }
}