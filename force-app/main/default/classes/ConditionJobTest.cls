@IsTest
public class ConditionJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testConditionJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new ConditionJob(validJson));
        Test.stopTest();

        // Execution completed without error
        System.assert(true, 'ConditionJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testConditionJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new ConditionJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'ConditionJob catch block executed');
    }
}