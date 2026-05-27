@RestResource(urlMapping='/medicalDelete/v1/*')
global without sharing class MedicalRecordsDeleteAPI {
    
    private static final String AUTHORIZATION_HEADER = 'x-api-key';
    private static final String METADATA_NAME = 'Medical_API';
    
   // Object Mapping
    private static final Map<String, String> OBJECT_TYPE_MAP = new Map<String, String>{
        'allergies' => 'AllergyIntolerance',
        'medications' => 'MedicationStatement',
        'medical_history' => 'HealthCondition',
        'surgical_history' => 'HealthCareProcedure',
        'basic_details' => 'Account',
        'insurance_details' => 'MemberPlan',
        'personal_contacts' => 'Contact',
        'healthcare_facilities' => 'HealthcareFacility',
        'healthcare_professionals' => 'HealthcarePractitionerFacility',
        'case_messages' => 'Case'
    };
    
    @HttpDelete
    global static void deleteRecord() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        
        BatchDeleteResponseWrapper batchResponse = new BatchDeleteResponseWrapper();
        
        if (!isRequestAuthorized(req)) {
            sendUnauthorizedResponse(res, batchResponse);
            return;
        }
        
        try {
            Map<String, Object> groupedData = parseRequestBody(req.requestBody.toString());
            processBatchDeletion(groupedData, batchResponse);
            res.statusCode = batchResponse.success ? 200 : 207;
            res.responseBody = Blob.valueOf(JSON.serialize(batchResponse));
        } catch (Exception e) {
            sendErrorResponse(res, batchResponse, 'Processing error: ' + e.getMessage(), 'PROCESSING_ERROR', 500);
        }
    }
    
    /* ========================= AUTH VALIDATION ========================= */
    private static Boolean isRequestAuthorized(RestRequest req) {
        String receivedKey = req.headers.get(AUTHORIZATION_HEADER);
        system.debug('reciveddatakey>>>'+receivedKey);
        
        if (String.isBlank(receivedKey)) {
            return false;
        }
        
        Encryption_Config__mdt cfg = Encryption_Config__mdt.getInstance(METADATA_NAME);
        
        if (cfg == null || String.isBlank(cfg.Secret_Key__c)) {
            return false;
        }
        
        return secureEquals(receivedKey, cfg.Secret_Key__c);
    }
    
    /* ========================= CONSTANT-TIME COMPARE ========================= */
    private static Boolean secureEquals(String a, String b) {
        if (a.length() != b.length()) {
            return false;
        }
        
        Integer result = 0;
        for (Integer i = 0; i < a.length(); i++) {
            result |= a.charAt(i) ^ b.charAt(i);
        }
        
        return result == 0;
    }
    

    private static void processBatchDeletion(
        Map<String, Object> groupedData, 
        BatchDeleteResponseWrapper batchResponse
    ) {
        List<SObject> allRecordsToDelete = new List<SObject>();
        Map<String, Integer> attemptedCountByGroup = new Map<String, Integer>();
        Map<String, List<Id>> recordIdsByGroup = new Map<String, List<Id>>();
        
        // Collect all records to delete
        for (String groupName : groupedData.keySet()) {
            collectRecordsForGroup(
                groupName, 
                groupedData.get(groupName), 
                allRecordsToDelete, 
                recordIdsByGroup, 
                attemptedCountByGroup,
                batchResponse
            );
        }
        if (!allRecordsToDelete.isEmpty()) {
            Database.DeleteResult[] results = Database.delete(allRecordsToDelete, false);
            processDeleteResults(results, allRecordsToDelete, recordIdsByGroup, attemptedCountByGroup, batchResponse);
        }
        batchResponse.success = batchResponse.failureCount == 0;
        batchResponse.message = batchResponse.success 
            ? 'All records deleted successfully' 
            : 'Batch deletion completed with partial failures';
    }
    
    private static void collectRecordsForGroup(
        String groupName,
        Object groupValue,
        List<SObject> allRecordsToDelete,
        Map<String, List<Id>> recordIdsByGroup,
        Map<String, Integer> attemptedCountByGroup,
        BatchDeleteResponseWrapper batchResponse
    ) {
        String objectType = normalizeObjectType(groupName);
        
        if (objectType == null) {
            batchResponse.failureCount++;
            return;
        }
        
        if (!(groupValue instanceof List<Object>)) {
            return;
        }
        
        List<Object> records = (List<Object>) groupValue;
        List<Id> validIds = new List<Id>();
        
        for (Object record : records) {
            try {
                Id recordId = extractRecordId(record);
                
                if (isValidRecordId(recordId, objectType)) {
                    SObject sobj = Schema.getGlobalDescribe().get(objectType).newSObject();
                    sobj.Id = recordId;
                    allRecordsToDelete.add(sobj);
                    validIds.add(recordId);
                } else {
                    batchResponse.failureCount++;
                }
            } catch (Exception ex) {
                batchResponse.failureCount++;
            }
        }
        
        if (!validIds.isEmpty()) {
            attemptedCountByGroup.put(groupName, validIds.size());
            recordIdsByGroup.put(groupName, validIds);
        }
    }
    
    private static void processDeleteResults(
        Database.DeleteResult[] results,
        List<SObject> records,
        Map<String, List<Id>> recordIdsByGroup,
        Map<String, Integer> attemptedCountByGroup,
        BatchDeleteResponseWrapper batchResponse
    ) {
        Map<String, Integer> successByGroup = new Map<String, Integer>();
        Map<String, Map<Id, String>> errorsByGroup = new Map<String, Map<Id, String>>();
        
        for (Integer i = 0; i < results.size(); i++) {
            Database.DeleteResult dr = results[i];
            SObject sobj = records[i];
            String objectTypeName = sobj.getSObjectType().getDescribe().getName();
            String groupKey = findGroupNameForObjectType(objectTypeName, recordIdsByGroup);
            
            if (dr.isSuccess()) {
                batchResponse.successCount++;
                Integer currentCount = successByGroup.containsKey(groupKey) ? successByGroup.get(groupKey) : 0;
                successByGroup.put(groupKey, currentCount + 1);
            } else {
                batchResponse.failureCount++;
                
                if (!errorsByGroup.containsKey(groupKey)) {
                    errorsByGroup.put(groupKey, new Map<Id, String>());
                }
                
                String errorMessage = dr.getErrors()[0].getMessage();
                errorsByGroup.get(groupKey).put(sobj.Id, errorMessage);
            }
        }
        
        // Build detailed response
        for (String groupKey : attemptedCountByGroup.keySet()) {
            batchResponse.details.put(groupKey, new Map<String, Object>{
                'totalAttempted' => attemptedCountByGroup.get(groupKey),
                'successful' => successByGroup.get(groupKey) != null ? successByGroup.get(groupKey) : 0,
                'failedRecords' => errorsByGroup.get(groupKey)
            });
        }
    }
    
    /* ========================= HELPER METHODS ========================= */
    private static Map<String, Object> parseRequestBody(String requestBody) {
        Object parsedBody = JSON.deserializeUntyped(requestBody);
        
        if (!(parsedBody instanceof Map<String, Object>)) {
            throw new IllegalArgumentException('Request body must be a JSON object');
        }
        
        return (Map<String, Object>) parsedBody;
    }
    
    private static Id extractRecordId(Object record) {
        if (record instanceof Map<String, Object>) {
            return (Id)((Map<String, Object>)record).get('id');
        }
        return (Id)record;
    }
    
    private static Boolean isValidRecordId(Id recordId, String expectedObjectType) {
        return recordId != null 
            && recordId.getSObjectType().getDescribe().getName() == expectedObjectType;
    }
    
    private static String findGroupNameForObjectType(
        String objectType,
        Map<String, List<Id>> recordIdsByGroup
    ) {
        for (String groupKey : recordIdsByGroup.keySet()) {
            if (normalizeObjectType(groupKey) == objectType) {
                return groupKey;
            }
        }
        return objectType;
    }
    
    private static String normalizeObjectType(String groupName) {
        String normalizedKey = groupName.toLowerCase().replaceAll('[^a-z0-9_]', '');
        return OBJECT_TYPE_MAP.get(normalizedKey);
    }
    
       
    private static void sendUnauthorizedResponse(
        RestResponse res, 
        BatchDeleteResponseWrapper batchResponse
    ) {
        batchResponse.success = false;
        batchResponse.message = 'Unauthorized request. Valid Authorization header required.';
        batchResponse.errorCode = 'INVALID_API_KEY';
        res.statusCode = 401;
        res.responseBody = Blob.valueOf(JSON.serialize(batchResponse));
    }
    
    private static void sendErrorResponse(
        RestResponse res,
        BatchDeleteResponseWrapper batchResponse,
        String message,
        String errorCode,
        Integer statusCode
    ) {
        batchResponse.success = false;
        batchResponse.message = message;
        batchResponse.errorCode = errorCode;
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(batchResponse));
    }
    
    global class BatchDeleteResponseWrapper {
        public Boolean success;
        public String message;
        public Integer successCount;
        public Integer failureCount;
        public String errorCode;
        public Map<String, Object> details;
        
        public BatchDeleteResponseWrapper() {
            this.success = true;
            this.successCount = 0;
            this.failureCount = 0;
            this.details = new Map<String, Object>();
        }
    }
}