public class CoverageJob implements Queueable {
    private String patientJson;
    public CoverageJob(String patientJson) { 
        this.patientJson = patientJson; 
    }
    public void execute(QueueableContext qc) {
               try {
            fhirObjectMappingHandler.parseAndInsertCoverages(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Coverages: ' + e.getMessage());
        }

}
}