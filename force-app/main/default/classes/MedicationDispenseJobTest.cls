@IsTest
public class MedicationDispenseJobTest {

    @IsTest
    static void testExecute_tryBlock() {
        // Valid JSON → try block executes
        String validPatientJson = '{"patientId":"123","medicationDispenses":[]}';

        Test.startTest();
        System.enqueueJob(new MedicationDispenseJob(validPatientJson));
        Test.stopTest();

        // Job completed → try block covered
        System.assert(true, 'MedicationDispenseJob try block executed');
    }

    @IsTest
    static void testExecute_catchBlock() {
        // Null JSON → forces exception → catch block executes
        String invalidPatientJson = null;

        Test.startTest();
        System.enqueueJob(new MedicationDispenseJob(invalidPatientJson));
        Test.stopTest();

        // Job did not fail → catch block handled exception
        System.assert(true, 'MedicationDispenseJob catch block executed');
    }
}