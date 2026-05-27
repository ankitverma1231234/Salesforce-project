public class EncounterJob implements Queueable {
    private String patientJson;
    public EncounterJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {
		
      /*  try {
            fhirObjectMapping.parseAndInsertLocations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Location: ' + e.getMessage());
        } */
        
        try {
            fhirObjectMapping.parseAndInsertEncounters(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Encounters: ' + e.getMessage());
        }
       
      /*  try {
            fhirObjectMapping.parseAndInsertOrganizations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Organization: ' + e.getMessage());
        } */
            
            
        
    }
}