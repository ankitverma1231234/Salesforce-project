public class MedicationRequestJob implements Queueable {
    private String patientJson;
    public MedicationRequestJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {

        
        try {
           MedicationHandler.parseAndInsertMedicationRequests(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in MedicationRequest: ' + e.getMessage());
        } 
        
}
}