public class RelatedPersonJob implements Queueable {
    private String patientJson;
    public RelatedPersonJob(String patientJson) { this.patientJson = patientJson; }

    public void execute(QueueableContext qc) {

         /* try {
        	MedicationHandler.parseAndInsertMedicationAdministrations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in MDA: ' + e.getMessage());
        } */
        
         try {
        fhirObjectMapping.parseAndInsertRelatedPersons(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in RelatedPersons: ' + e.getMessage());
        }

}
}