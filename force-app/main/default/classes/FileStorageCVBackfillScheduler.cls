public without sharing class FileStorageCVBackfillScheduler
    implements Schedulable {

    public static final String JOB_NAME =
        'File Storage ContentVersion Backfill - Every 15 Minutes';
    public static final List<String> FIFTEEN_MINUTE_CRONS =
        new List<String>{
            '0 0 * * * ?',
            '0 15 * * * ?',
            '0 30 * * * ?',
            '0 45 * * * ?'
        };
    public static final Integer BATCH_SIZE = 200;

    public void execute(SchedulableContext context) {
        Database.executeBatch(
            new FileStorageContentVersionBackfillBatch(),
            BATCH_SIZE
        );
    }

    public static List<Id> scheduleEveryFifteenMinutes() {
        List<Id> scheduledJobIds = new List<Id>();

        for (Integer index = 0; index < FIFTEEN_MINUTE_CRONS.size(); index++) {
            scheduledJobIds.add(
                (Id) System.schedule(
                    JOB_NAME + ' - ' + String.valueOf(index + 1),
                    FIFTEEN_MINUTE_CRONS[index],
                    new FileStorageCVBackfillScheduler()
                )
            );
        }

        return scheduledJobIds;
    }
}