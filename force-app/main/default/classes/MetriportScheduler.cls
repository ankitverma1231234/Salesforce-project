global class MetriportScheduler implements Schedulable, Database.AllowsCallouts {

    private String metriportPatientId;

    global MetriportScheduler(String metriportPatientId) {
        this.metriportPatientId = metriportPatientId;
    }

    global void execute(SchedulableContext sc) {

        MetripointfetchPateintDetails.startConsolidatedQuery(
            metriportPatientId
        );

        // Optional: clean up one-time job
        System.abortJob(sc.getTriggerId());
    }
}