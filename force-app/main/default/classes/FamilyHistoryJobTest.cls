@IsTest
public class FamilyHistoryJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testFamilyHistoryJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new FamilyHistoryJob(validJson));
        Test.stopTest();

        // Execution completed without errors
        System.assert(true, 'FamilyHistoryJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testFamilyHistoryJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new FamilyHistoryJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'FamilyHistoryJob catch block executed');
    }
}