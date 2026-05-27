@isTest
private class GeminiFileInsightBackfillSchedulerTest {
    
    @isTest
    static void testScheduleEveryNHoursCreatesExpectedJobs() {
        Test.startTest();
        GeminiFileInsightBackfillScheduler.scheduleEveryNHours(8, true, true);
        Test.stopTest();
        
        List<CronTrigger> cronJobs = [
            SELECT Id, CronJobDetail.Name, CronExpression, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'GeminiBackfill_H%'
        ];
        
        System.assertEquals(3, cronJobs.size(), 'Expected one job for each 8-hour interval');
        
        Set<String> names = new Set<String>();
        for (CronTrigger ct : cronJobs) {
            names.add(ct.CronJobDetail.Name);
            System.assert(ct.CronExpression.startsWith('0 0 '), 'Expected cron expression to start with trigger time');
        }
        
        System.assert(names.contains('GeminiBackfill_H0'));
        System.assert(names.contains('GeminiBackfill_H8'));
        System.assert(names.contains('GeminiBackfill_H16'));
    }
    
    @isTest
    static void testScheduleEvery6HoursUsesDefaultInterval() {
        Test.startTest();
        GeminiFileInsightBackfillScheduler.scheduleEvery6Hours();
        Test.stopTest();
        
        List<CronTrigger> cronJobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'GeminiBackfill_H%'
        ];
        
        System.assertEquals(4, cronJobs.size(), 'Expected four jobs for a 6-hour schedule');
    }
    
    @isTest
    static void testAbortExistingJobsRemovesActiveJobs() {
        Test.startTest();
        GeminiFileInsightBackfillScheduler.scheduleEveryNHours(12, false, false);
        List<CronTrigger> activeJobs = [
            SELECT Id, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'GeminiBackfill_H%'
            AND State != 'Deleted'
        ];
        System.assertEquals(2, activeJobs.size(), 'Expected two active scheduled jobs before abort');
        
        GeminiFileInsightBackfillScheduler.abortExistingJobs();
        
        List<CronTrigger> activeAfter = [
            SELECT Id, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'GeminiBackfill_H%'
            AND State != 'Deleted'
        ];
        System.assertEquals(0, activeAfter.size(), 'Expected no active scheduled jobs after abort');
        Test.stopTest();
    }
    
    @isTest
    static void testScheduleEveryNHoursInvalidIntervalThrows() {
        Test.startTest();
        try {
            GeminiFileInsightBackfillScheduler.scheduleEveryNHours(0, false, false);
            System.assert(false, 'Expected IllegalArgumentException for intervalHours=0');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('intervalHours must be between 1 and 23'));
        }
        
        try {
            GeminiFileInsightBackfillScheduler.scheduleEveryNHours(24, false, false);
            System.assert(false, 'Expected IllegalArgumentException for intervalHours=24');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('intervalHours must be between 1 and 23'));
        }
        Test.stopTest();
    }
    
    @isTest
    static void testExecuteSchedulesBatchWhenNoBatchRunning() {
        Test.startTest();
        new GeminiFileInsightBackfillScheduler().execute(null);
        
        Integer jobCount = [
            SELECT count()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'GeminiFileInsightBackfillBatch'
            AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        ];
        
        System.assertEquals(1, jobCount, 'Expected one backfill batch job when none were running');
        Test.stopTest();
    }
    
    @isTest
    static void testExecuteDoesNotScheduleWhenBatchRunning() {
        Test.startTest();
        Database.executeBatch(new GeminiFileInsightBackfillBatch(false, false), 1);
        
        Integer beforeCount = [
            SELECT count()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'GeminiFileInsightBackfillBatch'
            AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        ];
        System.assertEquals(1, beforeCount, 'Expected one active batch job before scheduler execution');
        
        new GeminiFileInsightBackfillScheduler().execute(null);
        
        Integer afterCount = [
            SELECT count()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'GeminiFileInsightBackfillBatch'
            AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
        ];
        System.assertEquals(1, afterCount, 'Expected no additional batch job when one is already running');
        Test.stopTest();
    }
}