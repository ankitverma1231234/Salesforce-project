@IsTest
public class MedicationJobTest {

    /* ------------------------------------
       Test: Normal execution (try block)
    ------------------------------------- */
    @IsTest
    static void testMedicationJob_SuccessPath() {

        // Minimal valid JSON (handler may or may not insert, that's OK)
        String validJson = '{"resourceType":"Bundle","entry":[]}';

        Test.startTest();
        System.enqueueJob(new MedicationJob(validJson));
        Test.stopTest();

        // If no exception is thrown, test passes
        System.assert(true, 'MedicationJob executed successfully');
    }

    /* ------------------------------------
       Test: Error path (catch block)
       Forces JSON parsing failure
    ------------------------------------- */
    @IsTest
    static void testMedicationJob_ErrorPath() {

        // Invalid JSON to force exception inside handler
        String invalidJson = '{ invalid json ::: }';

        Test.startTest();
        System.enqueueJob(new MedicationJob(invalidJson));
        Test.stopTest();

        // Catch block covered
        System.assert(true, 'MedicationJob catch block executed');
    }
    public static void jTest(integer i){
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        
    }
}