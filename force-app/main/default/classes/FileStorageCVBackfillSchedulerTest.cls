@IsTest
private class FileStorageCVBackfillSchedulerTest {
    @IsTest
    static void executeQueuesBackfillBatch() {
        Set<Id> existingJobIds = new Map<Id, AsyncApexJob>([
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name =
                'FileStorageContentVersionBackfillBatch'
        ]).keySet();

        Test.startTest();
        new FileStorageCVBackfillScheduler().execute(null);

        AsyncApexJob queuedJob = [
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name =
                'FileStorageContentVersionBackfillBatch'
            AND Id NOT IN :existingJobIds
            AND Status IN ('Holding', 'Queued', 'Preparing')
            LIMIT 1
        ];
        System.abortJob(queuedJob.Id);
        Test.stopTest();
    }
    
    @IsTest
    static void scheduleUsesEveryFifteenMinutesCron() {
        Test.startTest();
        List<Id> scheduledJobIds =
            FileStorageCVBackfillScheduler.scheduleEveryFifteenMinutes();

        List<CronTrigger> scheduledJobs = [
            SELECT Id, CronExpression
            FROM CronTrigger
            WHERE Id IN :scheduledJobIds
        ];

        Set<String> actualCronExpressions = new Set<String>();
        for (CronTrigger scheduledJob : scheduledJobs) {
            actualCronExpressions.add(scheduledJob.CronExpression);
        }

        System.assertEquals(4, scheduledJobIds.size());
        System.assertEquals(
            new Set<String>(
                FileStorageCVBackfillScheduler.FIFTEEN_MINUTE_CRONS
            ),
            actualCronExpressions
        );

        for (Id scheduledJobId : scheduledJobIds) {
            System.abortJob(scheduledJobId);
        }
        Test.stopTest();
    }
}