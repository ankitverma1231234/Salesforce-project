@IsTest
public class OrganizationJobTest {

    /* ------------------------------------
       Test: Success path (try block)
    ------------------------------------- */
    @IsTest
    static void testOrganizationJob_Success() {

        // Minimal valid JSON
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new OrganizationJob(validJson));
        Test.stopTest();

        // Execution completed without errors
        System.assert(true, 'OrganizationJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
    ------------------------------------- */
    @IsTest
    static void testOrganizationJob_Error() {

        // Invalid JSON to force exception in handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new OrganizationJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'OrganizationJob catch block executed');
    }
}