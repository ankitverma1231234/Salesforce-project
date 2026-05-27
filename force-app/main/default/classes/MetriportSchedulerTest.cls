@IsTest
private class MetriportSchedulerTest {

    @IsTest
    static void testSchedulerExecution() {

        // Create test patient Id
        String testPatientId = 'TEST_PATIENT_123';

        // Create instance of scheduler
        MetriportScheduler scheduler = new MetriportScheduler(testPatientId);

        // Schedule the job
        String cronExp = '0 0 0 1 1 ? 2099'; // Any future date

        Test.startTest();
        String jobId = System.schedule(
            'Test Metriport Scheduler Job',
            cronExp,
            scheduler
        );
        Test.stopTest();

        // Verify job was created
        System.assertNotEquals(null, jobId);


    }
}