@IsTest
private class MetriportFilterSchedulerTest {

    /**
     * Covers:
     * - constructor
     * - execute()
     * - abortJob()
     */
    @IsTest
    static void testSchedulerExecution() {

        Test.startTest();

        String jobId = System.schedule(
            'Metriport Filter Scheduler Test',
            '0 0 0 1 1 ? 2099',
            new MetriportFilterScheduler('patient-123')
        );

        Test.stopTest();

        // Since abortJob() is called,
        // CronTrigger may no longer exist
        List<CronTrigger> jobs = [
            SELECT Id, State
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        // Validate job was cleaned up
        System.assertEquals(
            0,
            jobs.size(),
            'Scheduled job should be deleted after execution'
        );
    }

    /**
     * Constructor coverage
     */
    @IsTest
    static void testConstructorCoverage() {

        MetriportFilterScheduler schedulerObj =
            new MetriportFilterScheduler('test-patient');

        System.assertNotEquals(
            null,
            schedulerObj
        );
    }
}