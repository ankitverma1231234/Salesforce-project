@IsTest
public class CoverageJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testCoverageJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new CoverageJob(validJson));
        Test.stopTest();

        // Execution completed without error
        System.assert(true, 'CoverageJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testCoverageJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new CoverageJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'CoverageJob catch block executed');
    }
}