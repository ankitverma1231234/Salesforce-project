public with sharing class DocFlowSendDocumentController {

    // Hardcoded demo config
    private static final String ENDPOINT =
        'https://docflow-access.preview.emergentagent.com/api/v1/documents/generate-links';

    private static final String AUTHORIZATION_HEADER =
        'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGJiY2FmOWItOGU1My00NmQ1LThlNDYtZDM2NmQ3NTBmZTNjIiwidGVuYW50X2lkIjoiYjNjODA0ZjItZjI5MS00M2NiLWJiMTMtOWE2ZTA2NDRiZmY3IiwiZXhwIjoxNzc0OTc0NzQ5fQ.S7iNsf-rQtPQkT_DzekSq8UqxbBUlpm6yLe0OBFs4AQ';

    private static final String TEMPLATE_ID = '1abdbd3a-0d75-4135-8ee6-5946957bed3f';
    private static final String DOCUMENT_NAME = 'NDA - Sequential Sign';
    private static final String ROUTING_TYPE = 'sequential';
    private static final String DELIVERY_MODE = 'email';
    private static final Boolean SEND_EMAIL = true;

    @AuraEnabled
    public static UiResult sendDocument(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        if (objectApiName != 'Account') {
            throw new AuraHandledException('This version supports Account only.');
        }

        Account acc = [
            SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE Id = :recordId
            LIMIT 1
        ];

        RequestPayload payload = buildPayload(acc);
        String requestJson = JSON.serialize(payload);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Authorization', AUTHORIZATION_HEADER);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);
        req.setBody(requestJson);

        Http http = new Http();
        HttpResponse res;

        try {
            res = http.send(req);
        } catch (Exception ex) {
            throw new AuraHandledException('DocFlow callout failed: ' + ex.getMessage());
        }

        Integer statusCode = res.getStatusCode();

        if (statusCode >= 200 && statusCode < 300) {
            UiResult result = new UiResult();
            result.success = true;
            result.message = 'Document initiated successfully.';
            return result;
        }

        throw new AuraHandledException(
            'DocFlow API error: ' + statusCode + ' - ' + res.getBody()
        );
    }

    private static RequestPayload buildPayload(Account acc) {
        RequestPayload payload = new RequestPayload();
        payload.template_id = TEMPLATE_ID;
        payload.document_name = DOCUMENT_NAME;
        payload.routing_type = ROUTING_TYPE;
        payload.delivery_mode = DELIVERY_MODE;
        payload.send_email = SEND_EMAIL;

        payload.recipients = new List<RecipientRequest>();

        RecipientRequest recipient1 = new RecipientRequest();
        recipient1.name = 'Daniel Kandler';
        recipient1.email = 'shivam@amroar.com';
        recipient1.role = 'signer';
        recipient1.routing_order = 1;
        recipient1.assigned_components = new List<String>{
            'signature_1774877849745',
            'merge_1774877870555'
        };
        payload.recipients.add(recipient1);

        RecipientRequest recipient2 = new RecipientRequest();
        recipient2.name = 'John Client';
        recipient2.email = 'kapoorshivam13@gmail.com';
        recipient2.role = 'signer';
        recipient2.routing_order = 2;
        recipient2.assigned_components = new List<String>{
            'signature_1774877919978',
            'merge_1774877622165',
            'merge_1774877666741'
        };
        payload.recipients.add(recipient2);

        payload.merge_fields = new Map<String, Object>{
            'account.name' => acc.Name,
            'account.billingaddress' => buildBillingAddress(acc)
        };

        return payload;
    }

    private static String buildBillingAddress(Account acc) {
        List<String> parts = new List<String>();

        if (!String.isBlank(acc.BillingStreet)) {
            parts.add(acc.BillingStreet);
        }
        if (!String.isBlank(acc.BillingCity)) {
            parts.add(acc.BillingCity);
        }
        if (!String.isBlank(acc.BillingState)) {
            parts.add(acc.BillingState);
        }
        if (!String.isBlank(acc.BillingPostalCode)) {
            parts.add(acc.BillingPostalCode);
        }
        if (!String.isBlank(acc.BillingCountry)) {
            parts.add(acc.BillingCountry);
        }

        return String.join(parts, ', ');
    }

    public class UiResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    public class RequestPayload {
        public String template_id;
        public String document_name;
        public String routing_type;
        public String delivery_mode;
        public Boolean send_email;
        public List<RecipientRequest> recipients;
        public Map<String, Object> merge_fields;
    }

    public class RecipientRequest {
        public String name;
        public String email;
        public String role;
        public Integer routing_order;
        public List<String> assigned_components;
    }
}