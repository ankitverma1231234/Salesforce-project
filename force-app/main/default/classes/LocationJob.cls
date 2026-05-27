public class LocationJob implements Queueable {
    private String patientJson;
    public LocationJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {
		
        try {
            fhirObjectMapping.parseAndInsertLocations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Location: ' + e.getMessage());
        }
        
             
            
        

}
}