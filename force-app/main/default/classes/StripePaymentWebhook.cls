@RestResource(urlMapping='/StripePaymentWebhooks/*')
global without sharing class StripePaymentWebhook {
    
    @HttpPost
    global static void handleStripePayment() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        String reqBody = req.requestBody.toString();
        
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(reqBody);
            String eventType = (String) payload.get('type');
            System.debug('Event Type: ' + eventType);
            
            Map<String, Object> data = (Map<String, Object>) payload.get('data');
            Map<String, Object> eventObject = (Map<String, Object>) data.get('object');
            
            // Initialize result variables
            StripePaymentHandler.Result result = null;
            StripeSubscriptionHandler.Result strresult = null;
            Boolean isSubscriptionEvent = false;
            
            if (eventType == 'charge.succeeded') {
                System.debug('Handling event: ' + eventType);
                result = StripePaymentHandler.processChargeSucceeded(eventObject);
                System.debug('Result: ' + result.success + ' - ' + result.message);
            }
            
            else if (eventType == 'checkout.session.completed') {
                System.debug('Handling event with retry: ' + eventType);
                result = StripePaymentHandler.processInvoicePaymentWithRetry(eventObject);
                System.debug('Result: ' + result.success + ' - ' + result.message);
            }
            
            else if (eventType == 'invoice.finalized') {
                System.debug('Handling event: ' + eventType);
                result = StripePaymentHandler.getSubscriptionIdFromEvent(eventObject);
                System.debug('Result: ' + result.success + ' - ' + result.message);
            }
            
            else if (eventType == 'customer.subscription.created' || eventType == 'customer.subscription.updated') {
                System.debug('Handling event: ' + eventType);
                strresult = StripeSubscriptionHandler.handleSubscriptionCreated(eventObject);
                isSubscriptionEvent = true;
                System.debug('Result: ' + strresult.success + ' - ' + strresult.message);
            }
            
            else {
                System.debug('Event ignored: ' + eventType);
                res.statusCode = 200;
                res.responseBody = Blob.valueOf('Event ignored.');
                return;
            }
            if (isSubscriptionEvent && strresult != null) {
                res.statusCode = strresult.success ? 200 : 500;
                res.responseBody = Blob.valueOf(strresult.message);
                System.debug('Subscription event response: ' + strresult.message);
            } else if (result != null) {
                res.statusCode = result.success ? 200 : 500;
                res.responseBody = Blob.valueOf(result.message);
                System.debug('Payment event response: ' + result.message);
            } 
            
            System.debug('Response Body: ' + res.responseBody.toString());
        } catch (Exception e) {
            System.debug('Webhook error: ' + e.getMessage());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('Internal Server Error: ' + e.getMessage());
        }
    }
}