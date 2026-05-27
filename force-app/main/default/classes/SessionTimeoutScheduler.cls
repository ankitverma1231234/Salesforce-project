public class SessionTimeoutScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        if (isBatchRunning()) {
            return;
        }

        Database.executeBatch(new SessionTimeoutBatch(), 200);
        System.debug('[SessionTimeout] Batch started at: ' + DateTime.now());
    }

    private static Boolean isBatchRunning() {
        return ![
            SELECT Id FROM AsyncApexJob
            WHERE  ApexClass.Name = 'SessionTimeoutBatch'
            AND    Status IN ('Holding','Queued','Preparing','Processing')
            LIMIT  1
        ].isEmpty();
    }

    public static void scheduleJobs() {

        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE  CronJobDetail.Name LIKE 'Message_SessionTimeOut_%'
        ]) {
            System.abortJob(ct.Id);
        }

        for (Integer min : new Integer[]{ 0,5,10,15,20,25,30,35,40,45,50,55 }) {
            System.schedule(
                'Message_SessionTimeOut_' + min,
                '0 ' + min + ' * * * ?',
                new SessionTimeoutScheduler()
            );
        }
    }
}