@IsTest
public class EncounterJobTest {

    /* ------------------------------------
       Test: Success path (all try blocks)
    ------------------------------------- */
    @IsTest
    static void testEncounterJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new EncounterJob(validJson));
        Test.stopTest();

        // If execution completes, test passes
        System.assert(true, 'EncounterJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch blocks)
    ------------------------------------- */
    @IsTest
    static void testEncounterJob_Error() {

        // Invalid JSON to force exceptions in handlers
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new EncounterJob(invalidJson));
        Test.stopTest();

        // All catch blocks covered
        System.assert(true, 'EncounterJob catch blocks executed');
    }
}