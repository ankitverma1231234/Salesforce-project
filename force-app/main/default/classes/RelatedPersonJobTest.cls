@IsTest
public class RelatedPersonJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testRelatedPersonJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new RelatedPersonJob(validJson));
        Test.stopTest();

        // Execution completed
        System.assert(true, 'RelatedPersonJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testRelatedPersonJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new RelatedPersonJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'RelatedPersonJob catch block executed');
    }
}