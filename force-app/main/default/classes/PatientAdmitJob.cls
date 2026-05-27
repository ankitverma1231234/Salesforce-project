public class PatientAdmitJob implements Queueable {
    private String patientJson;
    private String eventType;

    public PatientAdmitJob(String patientJson,String eventType) { 
        this.patientJson = patientJson; this.eventType = eventType; }

    public void execute(QueueableContext qc) {
		
        try {
            fhirObjectMapping.parseAndInsertLocations(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Location: ' + e.getMessage());
        }
        
        try {
            fhirObjectMappingHandler.parseAndInsertConditions(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Conndition : ' + e.getMessage());
        }
        
        try {
            fhirObjectMapping.parseAndInsertPractitioners(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Conndition : ' + e.getMessage());
        }
       
        try {
            fhirObjectMapping.parseAndInsertEncounters(patientJson);
        } catch (Exception e) {
            System.debug('❌ Error in Encounters: ' + e.getMessage());
        }
        
        
		if (!Test.isRunningTest()) {System.enqueueJob(new MetriportADTNotificationServiceQueueable(patientJson, eventType));
        }
    }
}