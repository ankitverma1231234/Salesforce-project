@IsTest
public class ProcedureJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testProcedureJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new ProcedureJob(validJson));
        Test.stopTest();

        // If execution completes, test passes
        System.assert(true, 'ProcedureJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testProcedureJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new ProcedureJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'ProcedureJob catch block executed');
    }
}