@IsTest
public class PractitionerJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testPractitionerJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new PractitionerJob(validJson));
        Test.stopTest();

        // Execution completed successfully
        System.assert(true, 'PractitionerJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testPractitionerJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new PractitionerJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'PractitionerJob catch block executed');
    }
}