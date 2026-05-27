public class ServiceJob implements Queueable {
    private String patientJson;
    public ServiceJob(String patientJson) { this.patientJson = patientJson; }

    public void execute(QueueableContext qc) {
	
     /*   try {
             fhirObjectMapping.parseBinaryAndUpdateAccount(patientJson); } catch (Exception e) {
            System.debug('❌ Error in Binary: ' + e.getMessage());
        } */
        try {
            fhirObjectMapping.parseAndInsertServiceRequests(patientJson);} catch (Exception e) {
            System.debug('❌ Error in Service Request: ' + e.getMessage());
        }
      /*  try {
        	MedicationHandler.parseAndInsertMedicationAdministrations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in MDA: ' + e.getMessage());
        } */
        
        	
        

    }
}