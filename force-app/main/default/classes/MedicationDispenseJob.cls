public class MedicationDispenseJob implements Queueable {
    private String patientJson;
    public MedicationDispenseJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {

        
        try {
           MedicationHandler.parseAndInsertMedicationDispenses(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in MedicationDispense: ' + e.getMessage());
        } 
        
}
}