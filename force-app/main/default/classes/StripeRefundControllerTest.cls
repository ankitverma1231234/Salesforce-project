@IsTest
public class StripeRefundControllerTest {
    private static void setupStripeConfig() {
        Stripe_Refund__c config = new Stripe_Refund__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            API_Key__c = 'sk_test_12345',
            Refund_Endpoint__c = 'https://api.stripe.com/v1/refunds'
        );
        insert config;
    }
    
    @IsTest
    Static void testSuccessfulRefund(){
        setupStripeConfig();
        Stripe_Transaction__c tx = new Stripe_Transaction__c(
            Payment_ID__c = 'pi_test_success',
            Amount__c = 10.00,
            Status__c = 'pending'
        );
        insert tx;
        
        Test.setMock(HttpCalloutMock.class, new StripeRefundMock());
        Test.startTest();
        String result = StripeRefundController.processRefund(tx.Id);
        Test.stopTest();
        System.assert(result.startsWith('Success'), 'Refund should be successful');
        Stripe_Transaction__c updatedTx = [SELECT Status__c, Refund_ID__c, Refund_Date__c FROM Stripe_Transaction__c WHERE Id = :tx.Id];
        System.AssertEquals('succeeded',updatedTx.Status__c);
    }
    
    @IsTest
    Static void testAlreadyRefundedTransaction(){
        setupStripeConfig();
        Stripe_Transaction__c tx = new Stripe_Transaction__c(
            Payment_ID__c = 'pi_test_success',
            Amount__c = 10.00,
            Status__c = 'succeeded'
        );
        insert tx;  
        Test.setMock(HttpCalloutMock.class, new stripeRefundMock());
        Test.startTest();
        String result = StripeRefundController.processRefund(tx.Id);
        Test.stopTest();
        System.assertEquals('Error: This transaction has already been refunded.', result);
    }
    @isTest
    static void MissingPaymentId(){
        setupStripeConfig();
        Stripe_Transaction__c tx = new Stripe_Transaction__c(
            Payment_ID__c = null,  
            Amount__c = 10.00,
            Status__c = 'pending'
        );
        insert tx;
        
        Test.startTest();
        String result = StripeRefundController.processRefund(tx.Id);
        Test.stopTest();
        
        System.assertEquals('Error: Missing Payment Intent ID.', result);
    }
    
    @isTest
    static void testMissingCustomSetting() {
        // No custom setting inserted
        Stripe_Transaction__c tx = new Stripe_Transaction__c(
            Payment_ID__c = 'pi_missing_config',
            Amount__c = 10.00,
            Status__c = 'pending'
        );
        insert tx;
        
        Test.startTest();
        String result = StripeRefundController.processRefund(tx.Id);
        Test.stopTest();
        
        System.assert(result.contains('Error: Stripe configuration is missing'), 'Should return missing config error');
    }
    
    @isTest
    static void testStripeApiErrorResponse() {
        setupStripeConfig();
        
        Stripe_Transaction__c tx = new Stripe_Transaction__c(
            Payment_ID__c = 'pi_test_error',
            Amount__c = 10.00,
            Status__c = 'pending'
        );
        insert tx;
        
        Test.setMock(HttpCalloutMock.class, new StripeRefundMock());
        
        Test.startTest();
        String result = StripeRefundController.processRefund(tx.Id);
        Test.stopTest();
        
        System.assert(result.contains('Error: The payment intent does not exist.'), 'Should handle Stripe error message');
    }
    @isTest
    static void testUnexpectedStripeResponse() {
        setupStripeConfig();
        
        Stripe_Transaction__c tx = new Stripe_Transaction__c(
            Payment_ID__c = 'pi_unexpected_response',
            Amount__c = 10.00,
            Status__c = 'pending'
        );
        insert tx;
        
        Test.setMock(HttpCalloutMock.class, new StripeRefundMock());
        
        Test.startTest();
        String result = StripeRefundController.processRefund(tx.Id);
        Test.stopTest();
        
        System.assertEquals('Error: Unexpected response from Stripe.', result);
    }
    
    @isTest
    static void updateRefundnote() {
        setupStripeConfig();
        
        Stripe_Transaction__c tx = new Stripe_Transaction__c(
            Payment_ID__c = 'pi_test_success',
            Amount__c = 10.00,
            Status__c = 'Paid',
            Notes__c = 'Test'
        );
        insert tx;
        
        String testNote = 'This is a test refund note';
        Test.setMock(HttpCalloutMock.class, new StripeRefundMock(testNote));
        
        
        Test.startTest();
        StripeRefundController.updateTransactionNotes(tx.Id, tx.Status__c);
        Test.stopTest();
        
        Stripe_Transaction__c updatedTx = [
            SELECT Notes__c, Status__c 
            FROM Stripe_Transaction__c 
            WHERE Id = :tx.Id
            LIMIT 1
        ];
    }
}