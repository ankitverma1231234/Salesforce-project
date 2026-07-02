public class MedicalSalesforceDeleteRecord {

    public static void deleteRecordFromThirdParty(Set<Id> recordIds, String recordType) {
        if(recordIds == null || recordIds.isEmpty()) {
            return;
        }
        List<Id> recordIdList = new List<Id>(recordIds);

        if (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() > 0) {
            System.enqueueJob(new DeleteRecordsQueueable(recordIdList, recordType));
        } else {
            System.debug(LoggingLevel.ERROR, 'Queueable limit reached, skipping delete for ' + recordType + '. Ids: ' + recordIdList);
        }
    }

    public static Map<String, Object> buildDeletePayload(List<Id> recordIds, String recordType) {
        Map<String, Object> payload = new Map<String, Object>();
        try {
            List<Map<String, Object>> items = new List<Map<String, Object>>();
            for(Id recordId : recordIds) {
                Map<String, Object> item = new Map<String, Object>();
                item.put('id', (String)recordId);
                items.add(item);
            }
            String jsonKey = getJsonKeyForRecordType(recordType);
            payload.put(jsonKey, items);
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error building delete payload: ' + ex.getMessage() +
                       '\nStack: ' + ex.getStackTraceString());
        }
        return payload;
    }

    public static String getJsonKeyForRecordType(String recordType) {
        Map<String, String> objectToKeyMap = new Map<String, String>{
            'AllergyIntolerance' => 'allergies',
            'Account' => 'basic_details',
            'MedicationStatement'  => 'medications',
            'HealthCondition' => 'medical_history',
            'HealthCareProcedure' => 'surgical_history',
            'MemberPlan' => 'insurance_details',
            'Contact' => 'personal_contacts',
            'HealthcareFacility' => 'healthcare_facilities',
            'HealthcarePractitionerFacility' => 'healthcare_professionals',
            'Case' => 'case_messages',
            'PatientImmunization' => 'immunization',
            'CareObservation'=> 'labs',
            'fra__File_Storage__c' => 'documents'
        };
        return objectToKeyMap.containsKey(recordType) ? objectToKeyMap.get(recordType) : recordType.toLowerCase();
    }

    public static HttpResponse sendDeleteHttpRequest(String endpoint, Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        String jsonPayload = JSON.serialize(payload);
        System.debug('deletepayload>>>' + jsonPayload);
        req.setBody(jsonPayload);
        Http http = new Http();
        HttpResponse res = http.send(req);
        return res;
    }
}