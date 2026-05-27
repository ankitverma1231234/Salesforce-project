public class FamilyHistoryJob implements Queueable {
    private String patientJson;
    public FamilyHistoryJob(String patientJson) { this.patientJson = patientJson; }

    public void execute(QueueableContext qc) {
        
		try {
            fhirObjectMapping.parseAndInsertFamilyMemberHistory(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Family History: ' + e.getMessage());
        }
        
        //MedicationHandler.parseAndInsertMedicationAdministrations(patientJson);
  
}
}