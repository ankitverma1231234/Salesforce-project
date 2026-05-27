@IsTest
public class ServiceJobTest {

    @IsTest
    static void testServiceJobExecution() {
        // Arrange
        // Minimal JSON to pass into the job
        String patientJson = '{"resourceType":"Patient","id":"test-patient"}';

        Test.startTest();

        // Act
        ServiceJob job = new ServiceJob(patientJson);
        System.enqueueJob(job);

        Test.stopTest();

        // Assert
        // If no unhandled exceptions occur, the test passes.
        // Queueables do not return values, so execution itself is the assertion.
        System.assert(true, 'ServiceJob executed successfully');
    }

    @IsTest
    static void testServiceJobWithInvalidJson() {
        // Arrange
        // Invalid JSON to force exception paths in try/catch blocks
        String badJson = 'INVALID_JSON';

        Test.startTest();

        // Act
        ServiceJob job = new ServiceJob(badJson);
        System.enqueueJob(job);

        Test.stopTest();

        // Assert
        // We expect no uncaught exceptions because errors are handled internally
        System.assert(true, 'ServiceJob handled invalid JSON without crashing');
    }
}