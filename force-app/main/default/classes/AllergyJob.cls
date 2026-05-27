public class AllergyJob implements Queueable {
    private String patientJson;
    public AllergyJob(String patientJson) {
        this.patientJson = patientJson;
    }
    public void execute(QueueableContext qc) {
        try {
           AllergyIntoleranceHandler.parseAndInsertAllergies(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Allergy: ' + e.getMessage());
        }
}
}