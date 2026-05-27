public class ObservationJob implements Queueable {
    private String patientJson;
    public ObservationJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {
		
     
            try {
            fhirObjectMapping.parseAndInsertObservations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Observation: ' + e.getMessage());
        }       
            
        

}
}