public class ImmunizationJob implements Queueable {

    private String patientJson;

    public ImmunizationJob(String patientJson) {
        this.patientJson = patientJson;
    }

    public void execute(QueueableContext qc) {
		
        
        try {
           ImmunizationHandler.parseAndInsertImmunizations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Immunization: ' + e.getMessage());
        }

}
}