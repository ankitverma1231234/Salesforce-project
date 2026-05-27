public class PractitionerJob implements Queueable {
    private String patientJson;
    public PractitionerJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {
		
     
              try {
            fhirObjectMapping.parseAndInsertPractitioners(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Practitioners: ' + e.getMessage());
        } 
            
        


}
}