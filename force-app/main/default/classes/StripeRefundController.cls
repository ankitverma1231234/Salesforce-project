public With Sharing class StripeRefundController {
    @AuraEnabled
    public static String processRefund(String transactionId) {
        try {
            Stripe_Refund__c config = Stripe_Refund__c.getOrgDefaults();
            if (config == null || String.isBlank(config.API_Key__c) || String.isBlank(config.Refund_Endpoint__c)) {
                return 'Error: Stripe configuration is missing in Custom Settings.';
            }
            // Query Trasaction Record
            Stripe_Transaction__c trs = [
                SELECT Id, Payment_ID__c,Amount__c,Status__c,Notes__c,Refund_Date__c,Refund_ID__c 
                FROM Stripe_Transaction__c 
                WHERE Id = :transactionId 
                LIMIT 1
            ];
            If(String.IsBlank(trs.Payment_ID__c)){
                return 'Error: Missing Payment Intent ID.'; 
            }
            if (trs.Status__c == 'succeeded') {
                return 'Error: This transaction has already been refunded.';
            }
            
            // Stripe API call
            HttpRequest req = new HttpRequest();
            req.setEndpoint(config.Refund_Endpoint__c);
            req.setMethod('POST');
            Blob headerValue = Blob.valueOf(config.API_Key__c + ':');
            String authHeader = 'Basic ' + EncodingUtil.base64Encode(headerValue);
            req.setHeader('Authorization', authHeader);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            // Set request body
            String body = 'payment_intent=' + EncodingUtil.urlEncode(trs.Payment_ID__c, 'UTF-8');
            req.setBody(body);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            System.debug('responseMap>>>'+responseMap);
            if (responseMap.containsKey('id')) {
                String refundId = (String) responseMap.get('id');
                String refundStatus = (String) responseMap.get('status');
                Integer refundAmount = (Integer) responseMap.get('amount');
                String currencies = (String) responseMap.get('currency');
                
                trs.Status__c = refundStatus;
                trs.Refund_ID__c = refundId;
                //transaction.Refund_Amount__c = refundAmount / 100.0;
                trs.Refund_Date__c = System.now();
                update trs;
                
                return 'Success: Refund completed. Refund ID: ' + refundId;
            } else if (responseMap.containsKey('error')) {
                Map<String, Object> err = (Map<String, Object>) responseMap.get('error');
                return 'Error: ' + err.get('message');
            }
            return 'Error: Unexpected response from Stripe.';
        } catch (Exception ex) {
            return 'Error: ' + ex.getMessage();
        }
    }

@AuraEnabled
public static void updateTransactionNotes(String transactionId, String notes) {
        Stripe_Transaction__c trans = [
            SELECT Id, Notes__c FROM Stripe_Transaction__c WHERE Id = :transactionId LIMIT 1
        ];
        try {
            trans.Notes__c = notes; 
            update trans;
        } catch (DmlException e) {
            System.debug('DML Error: ' + e.getMessage());
        }
    }
}