public class OrganizationJob implements Queueable {
    private String patientJson;
    public OrganizationJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {
		
       
        try {
            fhirObjectMapping.parseAndInsertOrganizations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Organization: ' + e.getMessage());
        }
            
            
        

}
}