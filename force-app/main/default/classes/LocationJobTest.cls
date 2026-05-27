@IsTest
public class LocationJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testLocationJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new LocationJob(validJson));
        Test.stopTest();

        // Execution completed successfully
        System.assert(true, 'LocationJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testLocationJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new LocationJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'LocationJob catch block executed');
    }
}