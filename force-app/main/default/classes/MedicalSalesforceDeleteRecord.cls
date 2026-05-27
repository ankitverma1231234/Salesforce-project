public class MedicalSalesforceDeleteRecord {    
    public static void deleteRecordFromThirdParty(Set<Id> recordIds, String recordType) {
        if(recordIds == null || recordIds.isEmpty()) {
            return;
        }
        List<Id> recordIdList = new List<Id>(recordIds);
        Integer batchSize = 10;         
        for(Integer i = 0; i < recordIdList.size(); i += batchSize) {
            Integer endIndex = Math.min(i + batchSize, recordIdList.size());
            List<Id> batchIds = new List<Id>();            
            for(Integer j = i; j < endIndex; j++) {
                batchIds.add(recordIdList[j]);
            }
            deleteRecordsFuture(JSON.serialize(batchIds), recordType);
        }
    }
    @future(callout=true)
    public static void deleteRecordsFuture(String recordIdsJson, String recordType) {
        try {
            List<Id> recordIds = (List<Id>)JSON.deserialize(recordIdsJson, List<Id>.class);
            BatonPortalAPI__c apiConfig = BatonPortalAPI__c.getOrgDefaults();
            if(apiConfig == null || String.isBlank(apiConfig.Delete_API_Key__c)) {
                System.debug(LoggingLevel.ERROR, 'Delete API configuration not found in Custom Setting');
                return;
            }
            String deleteEndpoint = apiConfig.Delete_API_Key__c;
            Map<String, Object> payload = buildDeletePayload(recordIds, recordType);
            if(payload == null || payload.isEmpty()) {
                System.debug('No data to delete');
                return;
            }            
            HttpResponse response = sendDeleteHttpRequest(deleteEndpoint, payload);
            if(response != null) {
                System.debug('Delete ' + recordType + ' - Response Code: ' + response.getStatusCode());                
                if(response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                    System.debug('Successfully deleted ' + recordType + ': ' + recordIds.size() + ' records');
                } else {
                    System.debug(LoggingLevel.ERROR, 'Failed to delete ' + recordType + 
                               '. Status: ' + response.getStatusCode() + 
                               ' Body: ' + response.getBody());
                }
            }            
        } catch(Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Delete error: ' + ex.getMessage() + 
                       '\nStack: ' + ex.getStackTraceString());
        }
    }
    private static Map<String, Object> buildDeletePayload(List<Id> recordIds, String recordType) {
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
    private static String getJsonKeyForRecordType(String recordType) {
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
            'ContentVersion' => 'documents'
        };        
        return objectToKeyMap.containsKey(recordType) ? objectToKeyMap.get(recordType) : recordType.toLowerCase();
    }
    private static HttpResponse sendDeleteHttpRequest(String endpoint, Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        String jsonPayload = JSON.serialize(payload);
        req.setBody(jsonPayload);        
        Http http = new Http();
        HttpResponse res = http.send(req);
        return res;
    }
}