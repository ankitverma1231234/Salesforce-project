public class SummaryJob implements Queueable {
    private String patientJson;
    public SummaryJob(String patientJson) { this.patientJson = patientJson; }

    public void execute(QueueableContext qc) {
	
        try {
             fhirObjectMapping.parseBinaryAndUpdateAccount(patientJson); } catch (Exception e) {
            System.debug('❌ Error in Binary: ' + e.getMessage());
        }

      /*  try {
        	MedicationHandler.parseAndInsertMedicationAdministrations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in MDA: ' + e.getMessage());
        } */
        
        	
        

    }
}