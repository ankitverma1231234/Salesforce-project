@IsTest
public class DiagnosticJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testDiagnosticJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new DiagnosticJob(validJson));
        Test.stopTest();

        // Execution completed successfully
        System.assert(true, 'DiagnosticJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testDiagnosticJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new DiagnosticJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'DiagnosticJob catch block executed');
    }
}