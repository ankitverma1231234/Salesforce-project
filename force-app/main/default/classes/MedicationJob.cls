public class MedicationJob implements Queueable {
    private String patientJson;
    public MedicationJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {

        //ImmunizationHandler.parseAndInsertImmunizations(json);
        try {
            fhirObjectMappingHandler.parseAndInsertMedications(patientJson);
        } catch (Exception e) {System.debug('❌ Error in Medication: ' + e.getMessage());
        }
        
        /*try {
           MedicationHandler.parseAndInsertMedicationRequests(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in MedicationRequest: ' + e.getMessage());
        } */
        
}
}