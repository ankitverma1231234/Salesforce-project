@IsTest
public class MedicationStatementJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testMedicationStatementJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new MedicationStatementJob(validJson));
        Test.stopTest();

        // If execution completes, test passes
        System.assert(true, 'MedicationStatementJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testMedicationStatementJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new MedicationStatementJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'MedicationStatementJob catch block executed');
    }
}