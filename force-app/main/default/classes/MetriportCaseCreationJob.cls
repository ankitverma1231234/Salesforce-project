public without sharing class MetriportCaseCreationJob
implements Queueable, Database.AllowsCallouts {

    private final Id accountId;

    private static final Integer DELAY_MINUTES = 2;

    public MetriportCaseCreationJob(Id accountId) {
        this.accountId = accountId;
    }

    public static void enqueueDelayed(Id accountId) {

    System.debug('enqueueDelayed called');

    AsyncOptions opts = new AsyncOptions();
    opts.MinimumQueueableDelayInMinutes = DELAY_MINUTES;

    Id jobId = System.enqueueJob(
        new MetriportCaseCreationJob(accountId),
        opts
    );

    System.debug('Queueable Job Id = ' + jobId);
}

    public void execute(QueueableContext ctx) {

        try {

            Id caseId =
                caseCreationController.createCaseAutomated(accountId);

            System.debug(
                'Case created automatically: '
                + caseId
            );

        } catch (Exception e) {

            logError(e.getMessage());
        }
    }

    private void logError(String message) {

        insert new Error_Log__c(
            Object_API_Name__c = 'Metriport Case Creation',
            Error_Message__c = message,
            Context__c = 'MetriportCaseCreationJob'
        );
    }

}