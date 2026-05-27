@IsTest
private class StripeSubscriptionHandlerTest2 {
    
    // Utility method to create a mock subscription payload
    private static Map<String, Object> createMockSubscriptionPayload(String interval, Integer intervalCount, Long currentPeriodStartEpoch) {
        // recurring map
        Map<String, Object> recurring = new Map<String, Object>{
            'interval' => interval,
            'interval_count' => intervalCount
        };

        // price map
        Map<String, Object> price = new Map<String, Object>{
            'recurring' => recurring
        };

        // first item
        Map<String, Object> firstItem = new Map<String, Object>{
            'current_period_start' => currentPeriodStartEpoch,
            'price' => price
        };

        // items list
        List<Object> dataList = new List<Object>{ firstItem };

        // items map
        Map<String, Object> items = new Map<String, Object>{
            'data' => dataList
        };

        // full subscription payload
        Map<String, Object> subscription = new Map<String, Object>{
            'id' => 'sub_test_123',
            'items' => items
        };

        return subscription;
    }

    // ✅ Positive test: Valid yearly subscription, opportunity found
    @IsTest
    static void testHandleSubscriptionCreated_ValidYearly() {
        // Create mock Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Subscription_Id__c = 'sub_test_123'
        );
        insert opp;

        // Create valid subscription payload
        Long nowEpoch = DateTime.now().getTime() / 1000;
        Map<String, Object> payload = createMockSubscriptionPayload('year', 1, nowEpoch);

        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(payload);
        Test.stopTest();

        System.assert(result.success, 'Expected success to be true');
        System.assert(result.message.contains('Opportunity updated'), 'Expected success message');

        // Verify opportunity update
        Opportunity updatedOpp = [SELECT Renewal_Date__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, updatedOpp.Renewal_Date__c, 'Renewal date should be set');
    }

    // ✅ Positive test: Valid monthly subscription
    @IsTest
    static void testHandleSubscriptionCreated_ValidMonthly() {
        Opportunity opp = new Opportunity(
            Name = 'Monthly Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(20),
            Subscription_Id__c = 'sub_test_123_monthly'
        );
        insert opp;

        Long nowEpoch = DateTime.now().getTime() / 1000;
        Map<String, Object> payload = createMockSubscriptionPayload('month', 3, nowEpoch);

        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(payload);
        Test.stopTest();

     }

    // ✅ Test: Valid daily subscription
    @IsTest
    static void testHandleSubscriptionCreated_ValidDaily() {
        Opportunity opp = new Opportunity(
            Name = 'Daily Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10),
            Subscription_Id__c = 'sub_test_123_daily'
        );
        insert opp;

        Long nowEpoch = DateTime.now().getTime() / 1000;
        Map<String, Object> payload = createMockSubscriptionPayload('day', 10, nowEpoch);

        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(payload);
        Test.stopTest();
    }

    // ⚠️ Test: Unsupported interval
    @IsTest
    static void testHandleSubscriptionCreated_UnsupportedInterval() {
        Long nowEpoch = DateTime.now().getTime() / 1000;
        Map<String, Object> payload = createMockSubscriptionPayload('week', 1, nowEpoch);

        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(payload);
        Test.stopTest();

        System.assert(!result.success, 'Expected failure for unsupported interval');
        System.assert(result.message.contains('Unsupported interval'), 'Expected unsupported interval message');
    }

    // ⚠️ Test: Subscription payload null
    @IsTest
    static void testHandleSubscriptionCreated_NullPayload() {
        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(null);
        Test.stopTest();

        System.assert(!result.success, 'Expected failure for null payload');
        System.assert(result.message.contains('null'), 'Expected null message');
    }

    // ⚠️ Test: Missing subscription ID
    @IsTest
    static void testHandleSubscriptionCreated_MissingId() {
        Map<String, Object> payload = new Map<String, Object>{
            'items' => new Map<String, Object>{ 'data' => new List<Object>() }
        };

        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(payload);
        Test.stopTest();

        System.assert(!result.success, 'Expected failure when ID is missing');
    }

    // ⚠️ Test: No Opportunity found
    @IsTest
    static void testHandleSubscriptionCreated_NoOpportunityFound() {
        Long nowEpoch = DateTime.now().getTime() / 1000;
        Map<String, Object> payload = createMockSubscriptionPayload('month', 1, nowEpoch);
        payload.put('id', 'sub_missing_999');

        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(payload);
        Test.stopTest();

        System.assert(!result.success, 'Expected failure for missing Opportunity');
        System.assert(result.message.contains('No Opportunity found'), 'Expected not found message');
    }

    // ⚠️ Test: current_period_start missing
    @IsTest
    static void testHandleSubscriptionCreated_MissingCurrentPeriodStart() {
        Map<String, Object> payload = createMockSubscriptionPayload('month', 1, null);
        // remove key intentionally
        ((Map<String, Object>)((List<Object>)((Map<String, Object>)payload.get('items')).get('data'))[0]).remove('current_period_start');

        Test.startTest();
        StripeSubscriptionHandler.Result result = StripeSubscriptionHandler.handleSubscriptionCreated(payload);
        Test.stopTest();

        System.assert(!result.success, 'Expected failure due to missing current_period_start');
    }
}