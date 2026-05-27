public class ConditionJob implements Queueable {
    private String patientJson;
    public ConditionJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {
        

        try {
            fhirObjectMappingHandler.parseAndInsertConditions(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Conditions: ' + e.getMessage());
        }
        
        //MedicationHandler.parseAndInsertMedicationAdministrations(patientJson);
        

        
        

}
}