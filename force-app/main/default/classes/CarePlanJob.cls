public class CarePlanJob implements Queueable {
    private String patientJson;
    public CarePlanJob(String patientJson) { this.patientJson = patientJson; }

    public void execute(QueueableContext qc) {


        try {
            fhirObjectMapping.parseAndInsertCarePlans(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in CarePlan: ' + e.getMessage());
        }
        
        
        

    }
}