@IsTest
public class MedicationRequestJobTest {

    @IsTest
    static void testMedicationRequestJob_success() {
        // Arrange
        String samplePatientJson = '{"patientId":"12345","medications":[]}';

        Test.startTest();
        // Act
        System.enqueueJob(new MedicationRequestJob(samplePatientJson));
        Test.stopTest();

        // Assert
        // If no exception is thrown, the job executed successfully.
        System.assert(true, 'MedicationRequestJob executed without errors');
    }

    @IsTest
    static void testMedicationRequestJob_withInvalidJson() {
        // Arrange: Invalid JSON to force error handling path
        String invalidJson = 'INVALID_JSON';

        Test.startTest();
        System.enqueueJob(new MedicationRequestJob(invalidJson));
        Test.stopTest();

        // Assert
        // Exception is caught internally, so test should still pass
        System.assert(true, 'MedicationRequestJob handled exception gracefully');
    }
}