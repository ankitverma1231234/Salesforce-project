global class MetriportScheduler implements Schedulable, Database.AllowsCallouts {

    private String metriportPatientId;

    global MetriportScheduler(String metriportPatientId) {
        this.metriportPatientId = metriportPatientId;
    }

    global void execute(SchedulableContext sc) {

        System.debug('=== METRIPORT SCHEDULER START ===');
        System.debug('Patient Id: ' + metriportPatientId);

        MetripointfetchPateintDetails.startConsolidatedQuery(
            metriportPatientId
        );

        System.debug('=== CONSOLIDATED QUERY STARTED ===');

        Account acc = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = :metriportPatientId
            LIMIT 1
        ];

        System.debug('=== ACCOUNT FOUND ===');
        System.debug('Account Id: ' + acc.Id);

        MetriportCaseCreationJob.enqueueDelayed(acc.Id);

        System.debug('=== CASE CREATION JOB QUEUED ===');

        //System.abortJob(sc.getTriggerId());
    }
}