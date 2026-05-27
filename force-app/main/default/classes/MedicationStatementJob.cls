public class MedicationStatementJob implements Queueable {
    private String patientJson;
    public MedicationStatementJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {
        
		try {
            fhirObjectMappingHandler.parseAndInsertMedicationStatements(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in MedicationStatements: ' + e.getMessage());
        }
        

}
}