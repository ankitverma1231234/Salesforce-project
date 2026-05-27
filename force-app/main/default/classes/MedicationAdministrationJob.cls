public class MedicationAdministrationJob implements Queueable {
    private String patientJson;
    public MedicationAdministrationJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {

        
        try {
          fhirObjectMappingHandler.parseAndInsertMedicationAdministrations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in MedicationAdministration: ' + e.getMessage());
        } 
        
}
}