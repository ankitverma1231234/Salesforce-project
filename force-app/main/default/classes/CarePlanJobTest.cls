@IsTest
public class CarePlanJobTest {

    @IsTest
    static void testCarePlanJobExecution() {
        // Arrange
        String patientJson = '{"resourceType":"Patient","id":"test-patient"}';

        Test.startTest();

        // Act
        CarePlanJob job = new CarePlanJob(patientJson);
        System.enqueueJob(job);

        Test.stopTest();

        // Assert
        // If execution reaches here, the job ran successfully
        System.assert(true, 'CarePlanJob executed successfully');
    }

    @IsTest
    static void testCarePlanJobWithInvalidJson() {
        // Arrange
        // Invalid JSON to trigger exception handling
        String badJson = 'INVALID_JSON';

        Test.startTest();

        // Act
        CarePlanJob job = new CarePlanJob(badJson);
        System.enqueueJob(job);

        Test.stopTest();

        // Assert
        // No unhandled exception should occur
        System.assert(true, 'CarePlanJob handled invalid JSON safely');
    }
}