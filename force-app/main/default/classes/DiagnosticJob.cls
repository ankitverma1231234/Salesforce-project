public class DiagnosticJob implements Queueable {
    private String patientJson;
    public DiagnosticJob(String patientJson) { 
        this.patientJson = patientJson; 
    }

    public void execute(QueueableContext qc) {

        try {
       fhirObjectMapping.parseAndInsertDiagnosticReports(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Diagnostic: ' + e.getMessage());
        }
       /* try {
            fhirObjectMapping.parseAndInsertCarePlans(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in CarePlan: ' + e.getMessage());
        } */
        
        
        


}
}