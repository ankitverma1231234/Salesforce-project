@isTest
private class StripeSubscriptionWebhookTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Subscription Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Subscription_Id__c = 'sub_test123456789'
        );
        insert opp;
    }
    
    // Test successful subscription.created event
    @isTest
    static void testSubscriptionCreatedSuccess() {
        // Prepare test data
        Opportunity opp = [SELECT Id, Subscription_Id__c FROM Opportunity LIMIT 1];
        
        // Build webhook payload for subscription.created
        Map<String, Object> webhookPayload = buildSubscriptionPayload(
            opp.Subscription_Id__c,
            'customer.subscription.created',
            'month',
            1
        );
        
        // Setup REST context
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        // Execute webhook
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        // Verify response
        System.assertEquals(200, res.statusCode, 'Should return 200 status code');
        
        // Verify Opportunity was updated
        Opportunity updatedOpp = [SELECT Id, Renewal_Date__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, updatedOpp.Renewal_Date__c, 'Renewal date should be set');
        
        // Verify renewal date is 1 month from current period start
        Date expectedRenewalDate = Date.today().addMonths(1);
        System.assertEquals(expectedRenewalDate, updatedOpp.Renewal_Date__c, 'Renewal date should be 1 month from start');
    }
    
    // Test successful subscription.updated event
    @isTest
    static void testSubscriptionUpdatedSuccess() {
        Opportunity opp = [SELECT Id, Subscription_Id__c FROM Opportunity LIMIT 1];
        
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
        
        System.assertEquals(200, res.statusCode, 'Should return 200 status code');
        
        Opportunity updatedOpp = [SELECT Id, Renewal_Date__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, updatedOpp.Renewal_Date__c, 'Renewal date should be set');
        
        Date expectedRenewalDate = Date.today().addYears(1);
        System.assertEquals(expectedRenewalDate, updatedOpp.Renewal_Date__c, 'Renewal date should be 1 year from start');
    }
    
    // Test subscription with daily interval
    @isTest
    static void testSubscriptionDailyInterval() {
        Opportunity opp = [SELECT Id, Subscription_Id__c FROM Opportunity LIMIT 1];
        
        Map<String, Object> webhookPayload = buildSubscriptionPayload(
            opp.Subscription_Id__c,
            'customer.subscription.created',
            'day',
            7
        );
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestBody = Blob.valueOf(JSON.serialize(webhookPayload));
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        StripePaymentWebhook.handleStripePayment();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200 status code');
        
        Opportunity updatedOpp = [SELECT Id, Renewal_Date__c FROM Opportunity WHERE Id = :opp.Id];
        Date expectedRenewalDate = Date.today().addDays(7);
        System.assertEquals(expectedRenewalDate, updatedOpp.Renewal_Date__c, 'Renewal date should be 7 days from start');
    }
    
    // Test subscription not found scenario
    @isTest
    static void testSubscriptionNotFound() {
        Map<String, Object> webhookPayload = buildSubscriptionPayload(
            'sub_nonexistent',
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
        
        System.assertEquals(500, res.statusCode, 'Should return 500 status code when opportunity not found');
        String responseBody = res.responseBody.toString();
        System.assert(responseBody.contains('No Opportunity found'), 'Response should indicate opportunity not found');
    }
    
    // Test null subscription payload
    @isTest
    static void testNullSubscriptionPayload() {
        Map<String, Object> webhookPayload = new Map<String, Object>{
            'type' => 'customer.subscription.created',
            'data' => new Map<String, Object>{
                'object' => null
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
        
        System.assertEquals(500, res.statusCode, 'Should return 500 for null payload');
    }
    
    // Test missing subscription ID
    @isTest
    static void testMissingSubscriptionId() {
        Map<String, Object> subscription = new Map<String, Object>{
            'items' => new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{
                        'current_period_start' => System.now().getTime() / 1000,
                        'price' => new Map<String, Object>{
                            'recurring' => new Map<String, Object>{
                                'interval' => 'month',
                                'interval_count' => 1
                            }
                        }
                    }
                }
            }
        };
        
        Map<String, Object> webhookPayload = new Map<String, Object>{
            'type' => 'customer.subscription.created',
            'data' => new Map<String, Object>{
                'object' => subscription
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
        
        System.assertEquals(500, res.statusCode, 'Should return 500 for missing subscription ID');
    }
    
    // Test missing items data
    @isTest
    static void testMissingItemsData() {
        Map<String, Object> subscription = new Map<String, Object>{
            'id' => 'sub_test123',
            'items' => new Map<String, Object>()
        };
        
        Map<String, Object> webhookPayload = new Map<String, Object>{
            'type' => 'customer.subscription.created',
            'data' => new Map<String, Object>{
                'object' => subscription
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
        
        System.assertEquals(500, res.statusCode, 'Should return 500 for missing items data');
    }
    
    // Test empty items data
    @isTest
    static void testEmptyItemsData() {
        Map<String, Object> subscription = new Map<String, Object>{
            'id' => 'sub_test123',
            'items' => new Map<String, Object>{
                'data' => new List<Object>()
            }
        };
        
        Map<String, Object> webhookPayload = new Map<String, Object>{
            'type' => 'customer.subscription.created',
            'data' => new Map<String, Object>{
                'object' => subscription
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
        
        System.assertEquals(500, res.statusCode, 'Should return 500 for empty items data');
    }
    
    // Test missing current_period_start
    @isTest
    static void testMissingCurrentPeriodStart() {
        Map<String, Object> subscription = new Map<String, Object>{
            'id' => 'sub_test123',
            'items' => new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{
                        'price' => new Map<String, Object>{
                            'recurring' => new Map<String, Object>{
                                'interval' => 'month',
                                'interval_count' => 1
                            }
                        }
                    }
                }
            }
        };
        
        Map<String, Object> webhookPayload = new Map<String, Object>{
            'type' => 'customer.subscription.created',
            'data' => new Map<String, Object>{
                'object' => subscription
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
        
        System.assertEquals(500, res.statusCode, 'Should return 500 for missing current_period_start');
    }
    
    // Test unsupported interval
    @isTest
    static void testUnsupportedInterval() {
        Opportunity opp = [SELECT Id, Subscription_Id__c FROM Opportunity LIMIT 1];
        
        Map<String, Object> webhookPayload = buildSubscriptionPayload(
            opp.Subscription_Id__c,
            'customer.subscription.created',
            'week',
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
        
        System.assertEquals(500, res.statusCode, 'Should return 500 for unsupported interval');
        String responseBody = res.responseBody.toString();
        System.assert(responseBody.contains('Unsupported interval'), 'Response should indicate unsupported interval');
    }
    
    // Test with interval_count as Long
    @isTest
    static void testIntervalCountAsLong() {
        Opportunity opp = [SELECT Id, Subscription_Id__c FROM Opportunity LIMIT 1];
        
        Long currentPeriodStart = System.now().getTime() / 1000;
        Map<String, Object> subscription = new Map<String, Object>{
            'id' => opp.Subscription_Id__c,
            'items' => new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{
                        'current_period_start' => currentPeriodStart,
                        'price' => new Map<String, Object>{
                            'recurring' => new Map<String, Object>{
                                'interval' => 'month',
                                'interval_count' => (Long)3
                            }
                        }
                    }
                }
            }
        };
        
        Map<String, Object> webhookPayload = new Map<String, Object>{
            'type' => 'customer.subscription.created',
            'data' => new Map<String, Object>{
                'object' => subscription
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
        
        System.assertEquals(200, res.statusCode, 'Should handle Long interval_count');
    }
    
    // Test ignored event type
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
        System.assertEquals('Event ignored.', res.responseBody.toString(), 'Should return ignored message');
    }
    
    // Test malformed JSON
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
    
    // Helper method to build subscription webhook payload
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
    
    // Test direct handler method - null payload
    @isTest
    static void testHandlerNullPayload() {
        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should return failure for null payload');
        System.assert(result.message.contains('null'), 'Message should mention null');
    }
    
    // Test direct handler method - missing price info
    @isTest
    static void testHandlerMissingPriceInfo() {
        Map<String, Object> subscription = new Map<String, Object>{
            'id' => 'sub_test123',
            'items' => new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{
                        'current_period_start' => System.now().getTime() / 1000
                    }
                }
            }
        };
        
        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(subscription);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Should return failure for missing price info');
    }
}