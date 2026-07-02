public class GuestAccountHeadRelationship {
   
    public class GuestAHRRequest {
        public Id       guestAccountId;
        public List<Id> memberAccountIds;
        
        public GuestAHRRequest(Id guestAccountId, List<Id> memberAccountIds) {
            this.guestAccountId   = guestAccountId;
            this.memberAccountIds = memberAccountIds;
        }
    }
    
    @future(callout=true)
    public static void sendGuestPayloadToPortal(Set<Id> guestAccountIds) {
        try {
            Map<Id, Account> guestAccountMap = new Map<Id, Account>([
                SELECT Id, FirstName, LastName, PersonEmail,
                PersonMobilePhone, Is_Guest__c, PersonContactId
                FROM Account
                WHERE Id IN :guestAccountIds
                AND Is_Guest__c = true
            ]);
            
            if (guestAccountMap.isEmpty()) {
                System.debug('No guest Accounts found — skipping callout.');
                return;
            }
            
            List<Account_Head_Relationship__c> ahrList = [
                SELECT Id,
                Member_Account__c,
                Authorized_Account_Access__c,
                Authorized_Account_Access__r.PersonContactId
                FROM Account_Head_Relationship__c
                WHERE Member_Account__c IN :guestAccountMap.keySet() AND  Authorized_Account_Access__c!= null];
            
            Map<Id, List<Map<String, String>>> guestToAccessMap =
                new Map<Id, List<Map<String, String>>>();
            
            for (Account_Head_Relationship__c ahr : ahrList) {
                Id guestId = ahr.Member_Account__c;
                
                if (!guestToAccessMap.containsKey(guestId)) {
                    guestToAccessMap.put(guestId, new List<Map<String, String>>());
                }
                
                guestToAccessMap.get(guestId).add(new Map<String, String>{
                    'accountId' => String.valueOf(ahr.Authorized_Account_Access__c),
                        'contactId' => String.valueOf(ahr.Authorized_Account_Access__r.PersonContactId)
                        });
            }
            
           
            List<Map<String, Object>> guestsPayload = new List<Map<String, Object>>();
            
            for (Id guestAccId : guestAccountMap.keySet()) {
                Account guestAcc = guestAccountMap.get(guestAccId);
                
                List<Map<String, String>> accessList = guestToAccessMap.containsKey(guestAccId)
                    ? guestToAccessMap.get(guestAccId)
                    : new List<Map<String, String>>();
                
               
                List<String> memberAccessIds = new List<String>();
                for (Map<String, String> entry : accessList) {
                    if (String.isNotBlank(entry.get('accountId'))) {
                        memberAccessIds.add(entry.get('accountId'));
                    }
                }
                
                guestsPayload.add(new Map<String, Object>{
                        'id'                  => String.valueOf(guestAccId),
                        'contactId'           => String.valueOf(guestAcc.PersonContactId),
                        'firstName'           => guestAcc.FirstName,
                        'lastName'            => guestAcc.LastName,
                        'is_guest'            => String.valueOf(guestAcc.Is_Guest__c),
                        'email'               => guestAcc.PersonEmail,
                        'phone'               => guestAcc.PersonMobilePhone,
                        'memberAccessDetails' => accessList
                        });
            }
            
            
            String jsonBody = JSON.serialize(new Map<String, Object>{
                'guests' => guestsPayload
                    });
            
            System.debug('Guest callout payload: ' + jsonBody);
            
            BatonPortalAPI__c settings = BatonPortalAPI__c.getOrgDefaults();
            String endpoint = settings.Api_Key__c;
            if (String.isBlank(endpoint)) {
                System.debug('API endpoint not configured in BatonPortalAPI__c.');
                return;
            }
            
            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(endpoint);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(jsonBody);
            httpReq.setTimeout(120000);
            
            HttpResponse httpRes = new Http().send(httpReq);
            
            if (httpRes.getStatusCode() == 200 || httpRes.getStatusCode() == 201) {
                System.debug('Guest payload sent successfully. Response: ' + httpRes.getBody());
            } else {
                System.debug('Guest callout failed. Status: '
                             + httpRes.getStatusCode() + ' Body: ' + httpRes.getBody());
            }
            
        } catch (Exception e) {
            System.debug('sendGuestPayloadToPortal error: '
                         + e.getMessage() + ' Line: ' + e.getLineNumber());
        }
    }
}