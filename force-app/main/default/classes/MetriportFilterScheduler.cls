global class MetriportFilterScheduler implements Schedulable, Database.AllowsCallouts {

    private String metriportPatientId;

    global MetriportFilterScheduler(String metriportPatientId) {
        this.metriportPatientId = metriportPatientId;
    }

    global void execute(SchedulableContext sc) {

         MetripointfetchPateintDetails.startClinicalSummaryQuery(
            metriportPatientId
        );
        

        // Optional: clean up one-time job
        System.abortJob(sc.getTriggerId());
    }
}