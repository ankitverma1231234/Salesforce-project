@isTest(SeeAllData=true)
private class StripePaymentWebhookCompleteTest {
    
    // ============================================
    // HELPER: Creates a Person Account for reuse across tests
    // ============================================
    private static Account createTestAccount(String firstName, String lastName, String email, String customerId, String stripeAccountId) {
        Id personAccountRT = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        
        Account acc = new Account(
            FirstName = firstName,
            LastName = lastName,
            PersonEmail = email,
            Customer_Id__c = customerId != null ? 'https://dashboard.stripe.com/customers/' + customerId : null,
            RecordTypeId = personAccountRT,
            Stripe_Account_Id__c = stripeAccountId
        );
        insert acc;
        return acc;
    }

    private static Opportunity createTestOpportunity(Id accountId, String subscriptionId) {
        Id oppRT = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Patient_Referral').getRecordTypeId();
        
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Subscription_Id__c = subscriptionId,
            RecordTypeId = oppRT
        );
        insert opp;
        return opp;
    }

    private static Stripe_Transaction__c createTestTransaction(Id accountId, Id opportunityId, String email, Decimal amount, String paymentId) {
        Stripe_Transaction__c txn = new Stripe_Transaction__c(
            Account__c = accountId,
            Opportunity__c = opportunityId,
            Amount__c = amount,
            Email__c = email,
            Payment_ID__c = paymentId
        );
        insert txn;
        return txn;
    }

    private static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User automatedUser = new User(
            Alias = 'autop',
            Email = 'autoproc@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'AutoProc',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'autoproc_' + uniqueSuffix + '@testorg.com'
        );
        insert automatedUser;
        return automatedUser;
    }

    // ============================================
    // CHARGE.SUCCEEDED EVENT TESTS
    // ============================================
    
    @isTest
    static void testChargeSucceededNewAccount() {
        createTestUser();

        Map<String, Object> webhookPayload = buildChargeSucceededPayload(
            'cus_new123',
            'pi_new123',
            'ch_new123',
            10000,
            'Premium Plan',
            true,
            'succeeded'
        );
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200 for successful charge');
        
        List<Account> accounts = [SELECT Id, FirstName, LastName, PersonEmail FROM Account 
                                  WHERE PersonEmail = 'new.customer@test.com'];
        System.assertEquals(1, accounts.size(), 'Should create new account');
        
        List<Opportunity> opps = [SELECT Id, Amount FROM Opportunity WHERE AccountId = :accounts[0].Id];
        System.assertEquals(1, opps.size(), 'Should create opportunity');
        System.assertEquals(100.00, opps[0].Amount, 'Amount should match');
    }
    
    @isTest
    static void testChargeSucceededExistingAccount() {
        createTestUser();
        Account acc = createTestAccount('John', 'Doe', 'john.doe.existing@test.com', 'cus_existing_test123', 'acct_test123');

        Map<String, Object> webhookPayload = buildChargeSucceededPayload(
            'cus_existing_test123',
            'pi_existing123',
            'ch_existing123',
            5000,
            'Basic Plan',
            true,
            'succeeded'
        );
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        List<Stripe_Transaction__c> txns = [SELECT Id, Amount__c, Account__c 
                                             FROM Stripe_Transaction__c 
                                             WHERE Payment_ID__c = 'pi_existing123'];
        System.assertEquals(1, txns.size(), 'Should create transaction for existing account');
        System.assertEquals(50.00, txns[0].Amount__c, 'Amount should match');
    }
    
    @isTest
    static void testChargeNotSucceeded() {
        Map<String, Object> webhookPayload = buildChargeSucceededPayload(
            'cus_fail123',
            'pi_fail123',
            'ch_fail123',
            10000,
            'Premium Plan',
            false,
            'failed'
        );
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(500, res.statusCode, 'Should return 500 for failed charge');
    }
    
    // ============================================
    // CHECKOUT.SESSION.COMPLETED EVENT TESTS
    // ============================================
    
    @isTest
    static void testCheckoutSessionCompletedSuccess() {
        createTestUser();
        Account acc = createTestAccount('John', 'Doe', 'john.doe.checkout@test.com', 'cus_checkout_test123', 'acct_test123');
        Opportunity opp = createTestOpportunity(acc.Id, 'sub_checkout_pre');
        createTestTransaction(acc.Id, null, 'john.doe.checkout@test.com', 100.00, 'pi_checkout_pre');

        Map<String, Object> webhookPayload = buildCheckoutSessionPayload(
            'cus_checkout_test123',
            'in_test123',
            'sub_checkout123',
            'subscription',
            'paid',
            'Premium Membership',
            'acct_stripe123'
        );
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        Account updatedAcc = [SELECT Id, Invoice_Id__c, Stripe_Account_Id__c 
                              FROM Account WHERE Id = :acc.Id];
        System.assertEquals('in_test123', updatedAcc.Invoice_Id__c, 'Invoice ID should be updated');
    }
    
    @isTest
    static void testCheckoutSessionMissingCustomer() {
        Map<String, Object> webhookPayload = buildCheckoutSessionPayload(
            null,
            'in_test123',
            'sub_test123',
            'subscription',
            'paid',
            'Premium Membership',
            'acct_stripe123'
        );
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(500, res.statusCode, 'Should return 500 for missing customer');
    }
    
    @isTest
    static void testCheckoutSessionAccountNotFound() {
        Map<String, Object> webhookPayload = buildCheckoutSessionPayload(
            'cus_nonexistent',
            'in_test123',
            'sub_test123',
            'subscription',
            'paid',
            'Premium Membership',
            'acct_stripe123'
        );
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(500, res.statusCode, 'Should return 500 when account not found');
    }
    
    // ============================================
    // INVOICE.FINALIZED EVENT TESTS
    // ============================================
    
    @isTest
    static void testInvoiceFinalizedSuccess() {
        createTestUser();
        Account acc = createTestAccount('John', 'Doe', 'john.doe.invoice@test.com', 'cus_invoice_test123', 'acct_test123');
        Opportunity opp = createTestOpportunity(acc.Id, 'sub_invoice_test123');
        createTestTransaction(acc.Id, null, 'john.doe.invoice@test.com', 100.00, 'pi_invoice_test123');

        Map<String, Object> webhookPayload = buildInvoiceFinalizedPayload(opp.Subscription_Id__c);
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        List<Stripe_Transaction__c> txns = [SELECT Id, Opportunity__c 
                                             FROM Stripe_Transaction__c 
                                             WHERE Opportunity__c = :opp.Id];
        System.assertEquals(1, txns.size(), 'Transaction should be linked to opportunity');
    }
    
    @isTest
    static void testInvoiceFinalizedNoOpportunity() {
        Map<String, Object> webhookPayload = buildInvoiceFinalizedPayload('sub_nonexistent');
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(500, res.statusCode, 'Should return 500 when opportunity not found');
    }
    
    // ============================================
    // SUBSCRIPTION EVENT TESTS
    // ============================================
    
    @isTest
    static void testSubscriptionCreatedSuccess() {
        createTestUser();
        Account acc = createTestAccount('John', 'Doe', 'john.doe.subcreated@test.com', 'cus_subcreated_test123', 'acct_test123');
        Opportunity opp = createTestOpportunity(acc.Id, 'sub_subcreated_test123');

        Map<String, Object> webhookPayload = buildSubscriptionPayload(
            opp.Subscription_Id__c,
            'customer.subscription.created',
            'month',
            1
        );
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        Opportunity updatedOpp = [SELECT Id, Renewal_Date__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, updatedOpp.Renewal_Date__c, 'Renewal date should be set');
    }
    
    @isTest
    static void testSubscriptionUpdatedSuccess() {
        createTestUser();
        Account acc = createTestAccount('John', 'Doe', 'john.doe.subupdated@test.com', 'cus_subupdated_test123', 'acct_test123');
        Opportunity opp = createTestOpportunity(acc.Id, 'sub_subupdated_test123');

        Map<String, Object> webhookPayload = buildSubscriptionPayload(
            opp.Subscription_Id__c,
            'customer.subscription.updated',
            'year',
            1
        );
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
    }
    
    // ============================================
    // ERROR HANDLING TESTS
    // ============================================
    
    @isTest
    static void testMalformedJSON() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf('{ invalid json }');
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(500, res.statusCode, 'Should return 500 for malformed JSON');
    }
    
    @isTest
    static void testIgnoredEventType() {
        Map<String, Object> webhookPayload = new Map<String, Object>{
            'type' => 'customer.created',
            'data' => new Map<String, Object>{
                'object' => new Map<String, Object>()
            }
        };
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200 for ignored events');
        System.assertEquals('Event ignored.', res.responseBody.toString());
    }
    
    // ============================================
    // DIRECT HANDLER METHOD TESTS
    // ============================================
    
    @isTest
    static void testProcessChargeSucceededDirectly() {
        createTestUser();

        Map<String, Object> charge = buildChargeObject(
            'cus_direct123',
            'pi_direct123',
            'ch_direct123',
            15000,
            'Elite Plan',
            true,
            'succeeded'
        );
        
        Test.startTest();
        StripePaymentHandler.Result result = StripePaymentHandler.processChargeSucceeded(charge);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should process charge successfully');
    }
    
    @isTest
    static void testGetSubscriptionIdFromEventDirectly() {
        createTestUser();
        Account acc = createTestAccount('John', 'Doe', 'john.doe.getsub@test.com', 'cus_getsub_test123', 'acct_test123');
        Opportunity opp = createTestOpportunity(acc.Id, 'sub_getsub_test123');
        createTestTransaction(acc.Id, null, 'john.doe.getsub@test.com', 100.00, 'pi_getsub_test123');

        Map<String, Object> invoice = buildInvoiceObject(opp.Subscription_Id__c);
        
        Test.startTest();
        StripePaymentHandler.Result result = StripePaymentHandler.getSubscriptionIdFromEvent(invoice);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should process invoice successfully');
    }
    
    @isTest
    static void testProcessInvoicePaymentWithRetryDirectly() {
        createTestUser();
        Account acc = createTestAccount('John', 'Doe', 'john.doe.retry@test.com', 'cus_retry_test123', 'acct_test123');
        Opportunity opp = createTestOpportunity(acc.Id, 'sub_retry_test123');
        createTestTransaction(acc.Id, null, 'john.doe.retry@test.com', 100.00, 'pi_retry_test123');

        Map<String, Object> session = buildCheckoutSessionObject(
            'cus_retry_test123',
            'in_direct123',
            'sub_direct123',
            'subscription',
            'paid',
            'Direct Test Plan',
            'acct_direct123'
        );
        
        Test.startTest();
        StripePaymentHandler.Result result = StripePaymentHandler.processInvoicePaymentWithRetry(session);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should process session successfully');
    }
    
    @isTest
    static void testChargeWithSingleNamePart() {
        createTestUser();

        Map<String, Object> charge = buildChargeObject(
            'cus_single123',
            'pi_single123',
            'ch_single123',
            10000,
            'Basic Plan',
            true,
            'succeeded'
        );
        
        // Override billing details with single name
        Map<String, Object> billingDetails = new Map<String, Object>{
            'email' => 'single@test.com',
            'name' => 'Madonna',
            'address' => new Map<String, Object>{
                'line1' => '123 Main St',
                'city' => 'Los Angeles',
                'state' => 'CA',
                'country' => 'US',
                'postal_code' => '90001'
            }
        };
        charge.put('billing_details', billingDetails);
        
        Test.startTest();
        StripePaymentHandler.Result result = StripePaymentHandler.processChargeSucceeded(charge);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should handle single name successfully');
        
        List<Account> accounts = [SELECT Id, FirstName, LastName FROM Account 
                                  WHERE PersonEmail = 'single@test.com'];
        System.assertEquals(1, accounts.size(), 'Should create account');
        System.assertEquals('Madonna', accounts[0].LastName, 'Should set last name correctly');
    }
    
    @isTest
    static void testChargeWithMultipleNameParts() {
        createTestUser();

        Map<String, Object> charge = buildChargeObject(
            'cus_multi123',
            'pi_multi123',
            'ch_multi123',
            10000,
            'Basic Plan',
            true,
            'succeeded'
        );
        
        Map<String, Object> billingDetails = new Map<String, Object>{
            'email' => 'multi@test.com',
            'name' => 'John Peter Doe',
            'address' => new Map<String, Object>()
        };
        charge.put('billing_details', billingDetails);
        
        Test.startTest();
        StripePaymentHandler.Result result = StripePaymentHandler.processChargeSucceeded(charge);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Should handle multiple names successfully');
        
        List<Account> accounts = [SELECT Id, FirstName, LastName FROM Account 
                                  WHERE PersonEmail = 'multi@test.com'];
        System.assertEquals('John', accounts[0].FirstName, 'Should set first name correctly');
        System.assertEquals('Peter Doe', accounts[0].LastName, 'Should set last name correctly');
    }
    
    // ============================================
    // HELPER METHODS
    // ============================================
    
    private static Map<String, Object> buildChargeSucceededPayload(
        String customerId,
        String paymentIntentId,
        String chargeId,
        Integer amount,
        String planName,
        Boolean paid,
        String status
    ) {
        Map<String, Object> charge = buildChargeObject(
            customerId, paymentIntentId, chargeId, amount, planName, paid, status
        );
        
        return new Map<String, Object>{
            'type' => 'charge.succeeded',
            'data' => new Map<String, Object>{
                'object' => charge
            }
        };
    }
    
    private static Map<String, Object> buildChargeObject(
        String customerId,
        String paymentIntentId,
        String chargeId,
        Integer amount,
        String planName,
        Boolean paid,
        String status
    ) {
        return new Map<String, Object>{
            'id' => chargeId,
            'paid' => paid,
            'status' => status,
            'payment_intent' => paymentIntentId,
            'customer' => customerId,
            'amount' => amount,
            'metadata' => new Map<String, Object>{
                'Plan_Name' => planName,
                'mode' => 'subscription'
            },
            'billing_details' => new Map<String, Object>{
                'email' => 'new.customer@test.com',
                'name' => 'New Customer',
                'address' => new Map<String, Object>{
                    'line1' => '123 Test St',
                    'city' => 'Test City',
                    'state' => 'CA',
                    'country' => 'US',
                    'postal_code' => '12345'
                }
            }
        };
    }
    
    private static Map<String, Object> buildCheckoutSessionPayload(
        String customerId,
        String invoiceId,
        String subscriptionId,
        String mode,
        String paymentStatus,
        String planName,
        String stripeAccountId
    ) {
        Map<String, Object> session = buildCheckoutSessionObject(
            customerId, invoiceId, subscriptionId, mode, 
            paymentStatus, planName, stripeAccountId
        );
        
        return new Map<String, Object>{
            'type' => 'checkout.session.completed',
            'data' => new Map<String, Object>{
                'object' => session
            }
        };
    }
    
    private static Map<String, Object> buildCheckoutSessionObject(
        String customerId,
        String invoiceId,
        String subscriptionId,
        String mode,
        String paymentStatus,
        String planName,
        String stripeAccountId
    ) {
        return new Map<String, Object>{
            'customer' => customerId,
            'invoice' => invoiceId,
            'subscription' => subscriptionId,
            'mode' => mode,
            'payment_status' => paymentStatus,
            'metadata' => new Map<String, Object>{
                'Plan_Name' => planName,
                'Stripe_account_id' => stripeAccountId
            },
            'customer_details' => new Map<String, Object>{
                'name' => 'John Doe',
                'phone' => '+1234567890'
            }
        };
    }
    
    private static Map<String, Object> buildInvoiceFinalizedPayload(String subscriptionId) {
        Map<String, Object> invoice = buildInvoiceObject(subscriptionId);
        
        return new Map<String, Object>{
            'type' => 'invoice.finalized',
            'data' => new Map<String, Object>{
                'object' => invoice
            }
        };
    }
    
    private static Map<String, Object> buildInvoiceObject(String subscriptionId) {
        return new Map<String, Object>{
            'lines' => new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{
                        'parent' => new Map<String, Object>{
                            'subscription_item_details' => new Map<String, Object>{
                                'subscription' => subscriptionId
                            }
                        }
                    }
                }
            }
        };
    }
    
    private static Map<String, Object> buildSubscriptionPayload(
        String subscriptionId,
        String eventType,
        String interval,
        Integer intervalCount
    ) {
        Long currentPeriodStart = System.now().getTime() / 1000;
        
        Map<String, Object> subscription = new Map<String, Object>{
            'id' => subscriptionId,
            'items' => new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{
                        'current_period_start' => currentPeriodStart,
                        'price' => new Map<String, Object>{
                            'recurring' => new Map<String, Object>{
                                'interval' => interval,
                                'interval_count' => intervalCount
                            }
                        }
                    }
                }
            }
        };
        
        return new Map<String, Object>{
            'type' => eventType,
            'data' => new Map<String, Object>{
                'object' => subscription
            }
        };
    }
}