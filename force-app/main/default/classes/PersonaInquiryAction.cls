public with Sharing class PersonaInquiryAction {
    public class InquiryRequest {
        @InvocableVariable(label='Person Account Id' required=true)
        public Id accountId;
        
        @InvocableVariable(label='Inquiry Template Id' required=true)
        public String templateId;   
    }
    
    public class InquiryResult {
        @InvocableVariable public String inquiryId;
        @InvocableVariable public String verificationUrl;
        @InvocableVariable public String status;
        @InvocableVariable public String errorMessage;  
    }
    
    @InvocableMethod(label = 'Create Persona Inquiry' description='Creates a Persona inquiry for a Person Account')
    public static List<InquiryResult> createInquiry(List<InquiryRequest> requests){
        List<InquiryResult> results = new List<InquiryResult>();
        List<Account> accountsToUpdate = new List<Account>();
        Set<Id> accountIds = new Set<Id>();
        for (InquiryRequest r : requests) {
            if (r.accountId != null) {
                accountIds.add(r.accountId);
            }
        }
        Map<Id, Account> accountMap  = New Map<Id, Account>([
            SELECT  Id,
            IsPersonAccount,
            FirstName,
            LastName,
            PersonEmail,
            PersonMobilePhone,
            PersonMailingStreet,
            PersonMailingCity,
            PersonMailingState,
            PersonMailingPostalCode,
            PersonMailingCountry
            FROM    Account
            WHERE   Id IN :accountIds]);
        
        for(InquiryRequest r: requests){
            InquiryResult result = new InquiryResult();
            if (!accountMap.containsKey(r.accountId)) {
                result.status       = 'Error';
                result.errorMessage = 'Person Account not found: ' + r.accountId;
                results.add(result);
                continue;
            }
            Account a = accountMap.get(r.accountId);
            try{
                // ── Split Street ──────────────────────────────
                String street1 = '';
                String street2 = '';
                if (a.PersonMailingStreet != null) {
                    List<String> lines = a.PersonMailingStreet.split('\n');
                    street1 = lines.size() > 0 ? lines[0] : '';
                    street2 = lines.size() > 1 ? lines[1] : '';
                }
                
                // ── Build JSON ────────────────────────────────
                String jsonBody =
                    '{"data":{' +
                    '"type":"inquiry",' +
                    '"attributes":{' +
                    '"inquiry-template-id":"' + r.templateId + '",' +
                    '"reference-id":"'        + a.Id         + '",' +
                    '"fields":{' +
                    '"name-first":"'          + escapeJson(a.FirstName)              + '",' +
                    '"name-last":"'           + escapeJson(a.LastName)               + '",' +
                    '"email-address":"'       + escapeJson(a.PersonEmail)            + '",' +
                    '"phone-number":"'        + escapeJson(a.PersonMobilePhone)      + '",' +
                    '"address-street-1":"'    + escapeJson(street1)                  + '",' +
                    '"address-street-2":"'    + escapeJson(street2)                  + '",' +
                    '"address-city":"'        + escapeJson(a.PersonMailingCity)      + '",' +
                    '"address-subdivision":"' + escapeJson(a.PersonMailingState)     + '",' +
                    '"address-postal-code":"' + escapeJson(a.PersonMailingPostalCode)+ '",' +
                    '"address-country-code":"US"' +
                    '}' +
                    '}' +
                    '}}';
                System.debug('Persona Request Body: ' + jsonBody);
                
                // HttpCallout
                HttpRequest req = new HttpRequest();
                req.setEndpoint('callout:Persona_API/api/v1/inquiries');
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setHeader('Persona-Version', '2025-12-08');
                req.setBody(jsonBody);
                Http http = new Http();
                HttpResponse res = http.send(req);
                System.debug('Persona Status'+ res.getStatusCode());
                System.debug('Persona Body: '   + res.getBody());
                
                if (res.getStatusCode() == 201) {
                    Map<String, Object> respBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    Map<String, Object> respData = (Map<String, Object>) respBody.get('data');
                    Map<String, Object> respAttrs = (Map<String, Object>) respData.get('attributes');
                   // Map<String, Object> respMeta = (Map<String, Object>) respBody.get('meta');
                    
                    String inquiryId = (String) respData.get('id');
                    String sessionToken = (String) respAttrs.get('session-token');
                    String verifyUrl    = 'https://withpersona.com/verify?inquiry-id='
                        + inquiryId
                        + '&session-token=' + sessionToken;
                    //String verifyUrl = (String) respMeta.get('one-time-link');
                    
                    System.debug('Inquiry ID: ' + inquiryId);
                    System.debug('Verify URL: ' + verifyUrl);
                    
                    result.inquiryId       = inquiryId;
                    result.verificationUrl = verifyUrl;
                    result.status          = 'Success';
                } else {
                    result.status       = 'Error';
                    result.errorMessage = 'HTTP ' + res.getStatusCode() + ' → ' + res.getBody();
                }
                
            } catch(Exception  ex){
                result.status       = 'Error';
                result.errorMessage = ex.getMessage() + ' | Line: ' + ex.getLineNumber();
                
            }
            results.add(result);
            
        }
        return results;   
    }  
    
    private static String escapeJson(String val) {
        if (val == null) return '';
        return val.replace('\\', '\\\\')
            .replace('"',  '\\"')
            .replace('\n', '\\n')
            .replace('\r', '\\r');
    }
}