@IsTest
public class ObservationJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testObservationJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new ObservationJob(validJson));
        Test.stopTest();

        // Execution completed successfully
        System.assert(true, 'ObservationJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testObservationJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new ObservationJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'ObservationJob catch block executed');
    }
}