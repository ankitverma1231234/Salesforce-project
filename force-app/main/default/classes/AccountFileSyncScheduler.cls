public without sharing class AccountFileSyncScheduler implements Schedulable {
    public static final String HOURLY_CRON = '0 0 * * * ?';
    public static final String DAILY_CRON = '0 0 1 * * ?';

    public void execute(SchedulableContext context) {
        Database.executeBatch(
            new AccountFileSyncInitiatorBatch(),
            AccountFileSyncInitiatorBatch.DEFAULT_ACCOUNT_BATCH_SIZE
        );
    }

    public static Id scheduleHourly() {
        return (Id) System.schedule(
            'Account File Sync - Hourly',
            HOURLY_CRON,
            new AccountFileSyncScheduler()
        );
    }

    public static Id scheduleDaily() {
        return (Id) System.schedule(
            'Account File Sync - Daily',
            DAILY_CRON,
            new AccountFileSyncScheduler()
        );
    }
}