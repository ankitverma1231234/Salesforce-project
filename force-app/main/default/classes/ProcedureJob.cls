public class ProcedureJob implements Queueable {
    private String patientJson;
    public ProcedureJob(String patientJson) {
        this.patientJson = patientJson; 
    }
    public void execute(QueueableContext qc) {
        try {
            fhirObjectMappingHandler.parseAndInsertProcedures(patientJson);
        } catch (Exception e) { System.debug('❌ Error in Procedure: ' + e.getMessage());
                              }
        /*  try {
MedicationHandler.parseAndInsertCoverages(patientJson);
} catch (Exception e) {
System.debug('❌ Error in Coverages: ' + e.getMessage());
} */

    }
}