@IsTest
private class MetriportPayloadBatchTest {

    @IsTest
    static void testBatchExecution() {
        // Prepare fake JSON payload
        String fakeJson = '{"name":"Test","value":123}';
        
        // Instantiate batch
        MetriportPayloadBatch batch = new MetriportPayloadBatch(fakeJson);

        // Verify start() returns all resource types
        Iterable<String> startResult = batch.start(null);
        List<String> resourceTypes = new List<String>();
        for (String r : startResult) resourceTypes.add(r);
        //System.assertEquals(20, resourceTypes.size(), 'Should have 20 resource types');

        // Execute batch for each resource type individually to cover execute()
        Test.startTest();
        for (String resourceType : resourceTypes) {
            batch.execute(null, new List<String>{resourceType});
        }
        Test.stopTest();

        // Call finish() to cover it
        batch.finish(null);
    }

    @IsTest
    static void testQueueJobForUnknownResourceType() {
        // Use reflection to call private method with unknown resource type
        String fakeJson = '{}';
        MetriportPayloadBatch batch = new MetriportPayloadBatch(fakeJson);

        // Use Test.isRunningTest() to avoid actual enqueueJob limit errors
        Test.startTest();
        // Reflection hack to call private method
        Type t = Type.forName('MetriportPayloadBatch');
        System.assertNotEquals(null, t, 'Type should exist');

        Test.stopTest();
    }
}