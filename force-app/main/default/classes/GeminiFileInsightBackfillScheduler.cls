public with sharing class GeminiFileInsightBackfillScheduler implements Schedulable {

    private static final Integer DEFAULT_INTERVAL_HOURS = 6;
    private static final Integer BATCH_SIZE             = 1;
    private static final String  JOB_NAME_PREFIX        = 'GeminiBackfill_H';

    private final Boolean forceRegenerate;
    private final Boolean attachPdf;

    // ── Constructors ──────────────────────────────────────────────────────────

    public GeminiFileInsightBackfillScheduler() {
        this(false, false);
    }

    public GeminiFileInsightBackfillScheduler(Boolean forceRegenerate, Boolean attachPdf) {
        this.forceRegenerate = forceRegenerate == true;
        this.attachPdf       = attachPdf == true;
    }

    // ── Schedulable ───────────────────────────────────────────────────────────

    public void execute(SchedulableContext sc) {
        if (isBatchRunning()) return;
        Database.executeBatch(
            new GeminiFileInsightBackfillBatch(forceRegenerate, attachPdf),
            BATCH_SIZE
        );
    }

    // ── Option 1 — parameterised N-hour interval ──────────────────────────────

    /**
     * Schedule the batch to fire every `intervalHours` hours.
     * Aborts any previously scheduled GeminiBackfill jobs first.
     *
     * Examples:
     *   GeminiFileInsightBackfillScheduler.scheduleEveryNHours(4, false, false);
     *   GeminiFileInsightBackfillScheduler.scheduleEveryNHours(7, true,  true);
     */
    public static void scheduleEveryNHours(
            Integer intervalHours,
            Boolean forceRegenerate,
            Boolean attachPdf) {

        if (intervalHours == null || intervalHours < 1 || intervalHours > 23) {
            throw new IllegalArgumentException(
                'intervalHours must be between 1 and 23, got: ' + intervalHours);
        }

        abortExistingJobs();

        GeminiFileInsightBackfillScheduler instance =
            new GeminiFileInsightBackfillScheduler(forceRegenerate, attachPdf);

        for (Integer hour : hoursForInterval(intervalHours)) {
            System.schedule(
                JOB_NAME_PREFIX + hour,
                '0 0 ' + hour + ' * * ?',
                instance
            );
        }
    }

    // ── Option 2 — default every-6-hours schedule ─────────────────────────────

    /**
     * Fires at 00:00, 06:00, 12:00, 18:00 UTC daily.
     * forceRegenerate=false, attachPdf=false.
     *
     * Example:
     *   GeminiFileInsightBackfillScheduler.scheduleEvery6Hours();
     */
    public static void scheduleEvery6Hours() {
        scheduleEveryNHours(DEFAULT_INTERVAL_HOURS, false, false);
    }

    // ── Abort helper ──────────────────────────────────────────────────────────

    public static void abortExistingJobs() {
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_PREFIX + '%'
        ]) {
            System.abortJob(ct.Id);
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static List<Integer> hoursForInterval(Integer intervalHours) {
        List<Integer> hours = new List<Integer>();
        for (Integer h = 0; h < 24; h += intervalHours) {
            hours.add(h);
        }
        return hours;
    }

    private static Boolean isBatchRunning() {
        return ![
            SELECT Id FROM AsyncApexJob
            WHERE  ApexClass.Name = 'GeminiFileInsightBackfillBatch'
            AND    Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            LIMIT  1
        ].isEmpty();
    }
}