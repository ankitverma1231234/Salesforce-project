public class MedicationStatementCleanupBatch
    implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    private static final Integer MONTHS_TO_RETAIN = 3;
    private static final Integer BATCH_SIZE        = 200;

    @TestVisible private Integer totalProcessed = 0;
    @TestVisible private Integer totalDeleted   = 0;
    @TestVisible private Integer totalFailed    = 0;


        public void execute(SchedulableContext sc) {
        Database.executeBatch(
            new MedicationStatementCleanupBatch(),
            BATCH_SIZE
        );
    }


    public Database.QueryLocator start(Database.BatchableContext bc) {
        DateTime cutoff = DateTime.now().addMonths(-MONTHS_TO_RETAIN);

        return Database.getQueryLocator([
            SELECT Id, CreatedDate
            FROM   MedicationStatement
            WHERE  CreatedDate < :cutoff
            ORDER BY CreatedDate ASC
        ]);
    }


    public void execute(
        Database.BatchableContext bc,
        List<SObject> scope
    ) {
        totalProcessed += scope.size();

        Database.DeleteResult[] results =
            Database.delete(scope, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                totalDeleted++;
            } else {
                totalFailed++;
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Delete failed | Id='     + scope[i].Id
                        + ' | StatusCode='        + err.getStatusCode()
                        + ' | Message='           + err.getMessage()
                    );
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
              '=== MedicationStatement Cleanup Complete ==='
            + ' | Scanned='  + totalProcessed
            + ' | Deleted='  + totalDeleted
            + ' | Failed='   + totalFailed
            + ' | Cutoff='   + DateTime.now().addMonths(-MONTHS_TO_RETAIN).format()
        );
    }


    public static String scheduleMonthEnd() {
        String jobId = System.schedule(
            'MedicationStatement_MonthEnd_Cleanup',
            '0 0 23 L * ?',
            new MedicationStatementCleanupBatch()
        );
        System.debug('Scheduled job id: ' + jobId);
        return jobId;
    }

    public static void abortExisting() {
        for (CronTrigger ct : [
            SELECT Id
            FROM   CronTrigger
            WHERE  CronJobDetail.Name = 'MedicationStatement_MonthEnd_Cleanup'
        ]) {
            System.abortJob(ct.Id);
        }
    }
}