public class MetriportPatientDocumentQueueable
    implements Queueable {

    private String rawJson;

    public MetriportPatientDocumentQueueable(String rawJson) {
        this.rawJson = rawJson;
    }

    public void execute(QueueableContext context) {

        if (String.isBlank(rawJson)) return;

        Map<String, Object> jsonData;
        try {
            jsonData = (Map<String, Object>) JSON.deserializeUntyped(rawJson);
        } catch (Exception e) {
            return;
        }

        if (jsonData == null) return;

        if (!'Bundle'.equals((String) jsonData.get('resourceType'))) return;

        Object entriesObj = jsonData.get('entry');
        if (!(entriesObj instanceof List<Object>)) return;

        for (Object o : (List<Object>) entriesObj) {

            if (!(o instanceof Map<String, Object>)) continue;

            Map<String, Object> entry = (Map<String, Object>) o;
            Object resourceObj = entry.get('resource');

            if (!(resourceObj instanceof Map<String, Object>)) continue;

            Map<String, Object> resource = (Map<String, Object>) resourceObj;

            if (!'Patient'.equals((String) resource.get('resourceType'))) continue;

            String patientId = (String) resource.get('id');
            system.debug('patientId 1'+ patientId);
            if (String.isBlank(patientId)) continue;
			system.debug('patientId 2'+ patientId);
            //All Documents Call  
            MetriportFetchPatientDocuments.fetchDocuments(patientId);
            //Medical Summary record
            MetriportFetchPatientSummary.fetchPatientSummary(patientId);
            //Mark Field is Checked 
            fhirObjectMapping.markAccountReadyToSend(patientId);
            
            system.debug('patientId 3'+ patientId);
        }
    }
}