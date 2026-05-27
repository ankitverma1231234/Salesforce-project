@RestResource(urlMapping='/OnboardingUpdate/v1/*')
global without sharing class MedicalRecordsUpdateAPI {
    
    private static final Integer MAX_RECORDS_PER_REQUEST = 1000;      
    private static final Integer MAX_RECORDS_PER_OBJECT_TYPE = 500; 
    
    @HttpPut
    global static void updateRecord() {
        
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        BatchResponseWrapper batchResponse = new BatchResponseWrapper();
        
        try {
            String requestBody = req.requestBody.toString();
            
            Object parsedBody = JSON.deserializeUntyped(requestBody);
            
            if (!(parsedBody instanceof Map<String, Object>)) {
                batchResponse.success = false;
                batchResponse.message = 'Invalid request format. Expected grouped JSON object.';
                batchResponse.errorCode = 'INVALID_REQUEST_FORMAT';
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(batchResponse));
                return;
            }
            
            Map<String, Object> groupedData = (Map<String, Object>) parsedBody;
            Map<String, List<Map<String, Object>>> recordsByType = new Map<String, List<Map<String, Object>>>();
            Map<String, String> objectTypeToGroupName = new Map<String, String>();
            
            for (String groupName : groupedData.keySet()) {
                
                String objectType = normalizeObjectType(groupName);
                
                if (objectType == null) {
                    batchResponse.failureCount++;
                    continue;
                }
                
                objectTypeToGroupName.put(objectType, groupName);
                
                Object value = groupedData.get(groupName);
                if (value instanceof List<Object>) {
                    if (!recordsByType.containsKey(objectType)) {
                        recordsByType.put(objectType, new List<Map<String, Object>>());
                    }
                    for (Object rec : (List<Object>) value) {
                        recordsByType.get(objectType).add((Map<String, Object>) rec);
                    }
                }
            }
            
            if (recordsByType.isEmpty()) {
                batchResponse.success = false;
                batchResponse.message = 'No valid record groups found in request.';
                batchResponse.errorCode = 'EMPTY_REQUEST';
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(batchResponse));
                return;
            }
            
            // Count total records and enforce limits
            Integer totalCount = 0;
            for (String key : recordsByType.keySet()) {
                totalCount += recordsByType.get(key).size();
            }
            
            // CHECK TOTAL RECORD LIMIT
            if (totalCount > MAX_RECORDS_PER_REQUEST) {
                batchResponse.success = false;
                batchResponse.message = 'Request exceeds maximum limit of ' + MAX_RECORDS_PER_REQUEST + 
                    ' records. Received: ' + totalCount + ' records. Please split your request into smaller batches.';
                batchResponse.errorCode = 'RECORD_LIMIT_EXCEEDED';
                batchResponse.totalRecords = totalCount;
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(batchResponse));
                return;
            }
            
            batchResponse.totalRecords = totalCount;
            
            for (String objectType : recordsByType.keySet()) {
                List<Map<String, Object>> recs = recordsByType.get(objectType);
                String originalGroupName = objectTypeToGroupName.get(objectType);
                
                // CHECK PER-OBJECT-TYPE LIMIT
                if (recs.size() > MAX_RECORDS_PER_OBJECT_TYPE) {
                    List<Map<String, Object>> groupResults = new List<Map<String, Object>>();
                    
                    for (Map<String, Object> recData : recs) {
                        ResponseWrapper resp = new ResponseWrapper();
                        resp.success = false;
                        resp.message = objectType + ' exceeds maximum limit of ' + MAX_RECORDS_PER_OBJECT_TYPE + ' records per object type. Received: ' + recs.size() + ' records.';             
                        resp.errorCode = 'OBJECT_TYPE_LIMIT_EXCEEDED';
                        resp.objectType = objectType;
                        resp.recordData = recData;
                        
                        groupResults.add(recData);
                        batchResponse.failureCount++;
                    }
                    
                    batchResponse.data.put(originalGroupName, groupResults);
                    continue; 
                }
                
                List<ResponseWrapper> typeResults = processBulkUpdateByType(objectType, recs);
                List<Map<String, Object>> groupResults = new List<Map<String, Object>>();
                
                for (ResponseWrapper resp : typeResults) {
                    if (resp.recordData != null) {
                        groupResults.add(resp.recordData);
                    }
                    
                    if (resp.success) batchResponse.successCount++;
                    else batchResponse.failureCount++;
                }
                
                batchResponse.data.put(originalGroupName, groupResults);
            }
            
            batchResponse.success = (batchResponse.failureCount == 0);
            batchResponse.message =
                'Processed ' + batchResponse.totalRecords +
                ' record(s): ' + batchResponse.successCount +
                ' succeeded, ' + batchResponse.failureCount + ' failed';
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(batchResponse));
            
        } catch (Exception e) {
            batchResponse.success = false;
            batchResponse.message = 'Unexpected error occurred during batch processing';
            batchResponse.errorDetails = e.getMessage();
            batchResponse.errorStackTrace = e.getStackTraceString();
            
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(batchResponse));
        }
    }
    
    // normalize method  
    private static String normalizeObjectType(String key) {
        Map<String, String> mapTypes = new Map<String, String>{
                'allergy'               => 'AllergyIntolerance',
                'allergies'             => 'AllergyIntolerance',
                
                'medication'            => 'MedicationStatement',
                'medications'           => 'MedicationStatement',
                
                'medical_history'       => 'HealthCondition',
                'medicalhistory'        => 'HealthCondition',
                
                'surgical_history'      => 'HealthCareProcedure',
                'surgicalhistory'       => 'HealthCareProcedure',
                
                'basic_details'         => 'Account',
                'basicdetails'          => 'Account',
                
                'insurance_details'     => 'MemberPlan',
                'insurancedetails'      => 'MemberPlan',
                
                'personal_contacts'     => 'Contact',
                'personalcontacts'      => 'Contact',
                
                'healthcare_facilities' => 'HealthcareFacility',
                'healthcarefacilities'  => 'HealthcareFacility',
                
                'healthcare_professionals' => 'HealthcarePractitionerFacility',
                'healthcareprofessionals'  => 'HealthcarePractitionerFacility',
                'document'   => 'ContentVersion'
                };
                    
                    key = key.toLowerCase();
        return mapTypes.containsKey(key) ? mapTypes.get(key) : null;
    }
    
    /* ============================================================================
PROCESS BULK UPDATE BY TYPE - Routes to specific bulk method
============================================================================ */
    @TestVisible
    private static List<ResponseWrapper> processBulkUpdateByType(String objectType, List<Map<String, Object>> records) {
        if (objectType == 'HealthCareProcedure') {
            return bulkUpdateSurgery(records);
        } else if (objectType == 'HealthCondition') {
            return bulkUpdateMedicalHistory(records);
        } else if (objectType == 'AllergyIntolerance') {
            return bulkUpdateAllergy(records);
        } else if (objectType == 'MedicationStatement') {
            return bulkUpdateMedication(records);
        } else if (objectType == 'MemberPlan') {
            return bulkUpdateInsurancePlan(records);
        } else if (objectType == 'HealthcareFacility') {
            return bulkUpdateHealthcareFacility(records);
        } else if (objectType == 'HealthcarePractitionerFacility') {
            return bulkUpdateHealthcareProfessional(records);
        } else if (objectType == 'Contact') {
            return bulkUpdatePersonalContact(records);
        } else if (objectType == 'Account') {
            return bulkUpdatePersonAccount(records);
        } else if (objectType == 'ContentVersion') {
            return bulkUpsertFiles(records);
        }
        else {
            List<ResponseWrapper> errorResults = new List<ResponseWrapper>();
            for (Map<String, Object> record : records) {
                ResponseWrapper response = new ResponseWrapper();
                response.success = false;
                response.message = 'Unsupported object type: ' + objectType;
                response.errorCode = 'UNSUPPORTED_OBJECT_TYPE';
                errorResults.add(response);
            }
            return errorResults;
        }
    }
    
    /* ============================================================================
AUTO-DETECT OBJECT TYPE FROM RECORD ID
============================================================================ */
    private static String detectObjectType(String recordId) {
        try {
            Id recId = Id.valueOf(recordId);
            Schema.SObjectType sobjectType = recId.getSObjectType();
            return sobjectType.getDescribe().getName();
        } catch (Exception e) {
            System.debug('Error detecting object type: ' + e.getMessage());
            return null;
        }
    }
    
    /* ============================================================================
BULK UPDATE SURGERY - Using HealthCareProcedure Object
============================================================================ */
    private static List<ResponseWrapper> bulkUpdateSurgery(List<Map<String, Object>> records) {
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        if (records == null || records.isEmpty()) {
            return responses;
        }
        
        Set<String> updateIds = new Set<String>();
        
        for (Map<String, Object> record : records) {
            if (record == null) continue; 
            
            String recordId = (String) record.get('id');
            if (!String.isBlank(recordId)) {
                updateIds.add(recordId);
            }
        }
        
        // Query existing HealthCareProcedure records
        Map<String, HealthCareProcedure> surgeryMap = new Map<String, HealthCareProcedure>();
        if (!updateIds.isEmpty()) {
            HealthCareProcedure[] existingRecs = [
                SELECT Id, Name,Surgery_Name__c, CodeDescription,
                EffectiveDate, Patient__c
                FROM HealthCareProcedure
                WHERE Id IN :updateIds
            ];
            for (HealthCareProcedure s : existingRecs) {
                if (s != null && s.Id != null) { 
                    surgeryMap.put(s.Id, s);
                }
            }
        }
        
        List<HealthCareProcedure> toUpdate = new List<HealthCareProcedure>();
        List<HealthCareProcedure> toInsert = new List<HealthCareProcedure>();
        Map<Integer, Map<String, Object>> insertIndexToData = new Map<Integer, Map<String, Object>>();
        Map<String, Map<String, Object>> updateIdToData = new Map<String, Map<String, Object>>();
        Integer insertIndex = 0;
        
        for (Map<String, Object> bodyData : records) {
            if (bodyData == null) continue; 
            
            String recordId = (String) bodyData.get('id');
            Boolean isCreate = (recordId == null || String.isBlank(recordId));
            HealthCareProcedure surgery;
            
            if (isCreate) {
                surgery = new HealthCareProcedure();
                toInsert.add(surgery);
                insertIndexToData.put(insertIndex++, bodyData);
            } else {
                surgery = surgeryMap.get(recordId);
                if (surgery == null) {
                    ResponseWrapper resp = new ResponseWrapper();
                    resp.success = false;
                    resp.message = 'Surgery record not found: ' + recordId;
                    resp.errorCode = 'RECORD_NOT_FOUND';
                    resp.recordId = recordId;
                    resp.objectType = 'HealthCareProcedure';
                    resp.recordData = bodyData;
                    responses.add(resp);
                    continue;
                }
                toUpdate.add(surgery);
                updateIdToData.put(recordId, bodyData);
            }
            
            
            if (bodyData.containsKey('name') && bodyData.get('name') != null) {
                surgery.Name = (String) bodyData.get('name');
                surgery.Surgery_Name__c = (String) bodyData.get('name');
            }
            
            if (bodyData.containsKey('surgeryDate') && bodyData.get('surgeryDate') != null) {
                surgery.EffectiveDate = parseDate(bodyData.get('surgeryDate'));
            }
            
            if (bodyData.containsKey('note') && bodyData.get('note') != null) {
                surgery.CodeDescription = (String) bodyData.get('note');
            }           
            if (isCreate && bodyData.containsKey('accountId') && bodyData.get('accountId') != null) {
                surgery.Patient__c = (String) bodyData.get('accountId');
            }
        }
        
        // --- Perform UPDATE ---
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                HealthCareProcedure surgery = toUpdate[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.recordId = surgery != null ? surgery.Id : null; 
                resp.objectType = 'HealthCareProcedure';
                resp.recordData = surgery != null ? updateIdToData.get(surgery.Id) : null;
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Surgery record updated successfully';
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to update surgery: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                }
                responses.add(resp);
            }
        }
        
        // --- Perform INSERT ---
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.objectType = 'HealthCareProcedure';
                resp.recordData = insertIndexToData.get(i);
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Surgery record created successfully';
                    resp.recordId = sr.getId();
                    
                    if (resp.recordData != null) {
                        resp.recordData.put('id', sr.getId());
                    }
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to create surgery: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                    system.debug('resp.message--> create surgery: ' + resp.message);
                }
                responses.add(resp);
            }
        }
        
        return responses;
    }
    /* ============================================================================
BULK UPDATE MEDICAL HISTORY - Using HealthCondition Object
============================================================================ */
    private static List<ResponseWrapper> bulkUpdateMedicalHistory(List<Map<String, Object>> records) {
        
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        if (records == null || records.isEmpty()) {
            return responses;
        }
        
        Set<String> updateIds = new Set<String>();
        
        for (Map<String, Object> record : records) {
            if (record == null) continue; 
            
            String recordId = (String) record.get('id');
            if (!String.isBlank(recordId)) {
                updateIds.add(recordId);
            }
        }
        
        // Query existing HealthCondition records
        Map<String, HealthCondition> historyMap = new Map<String, HealthCondition>();
        if (!updateIds.isEmpty()) {
            HealthCondition[] existingRecs = [
                SELECT Id, Name, ProblemName, ProblemDescription, OnsetStartDateTime,ConditionStatus, 
                Severity, PatientId
                FROM HealthCondition
                WHERE Id IN :updateIds
            ];
            for (HealthCondition mh : existingRecs) {
                if (mh != null && mh.Id != null) { 
                    historyMap.put(mh.Id, mh);
                }
            }
        }
        
        // Lists for insert & update
        List<HealthCondition> toUpdate = new List<HealthCondition>();
        List<HealthCondition> toInsert = new List<HealthCondition>();
        Map<Integer, Map<String, Object>> insertIndexToData = new Map<Integer, Map<String, Object>>();
        Map<String, Map<String, Object>> updateIdToData = new Map<String, Map<String, Object>>();
        Integer insertIndex = 0;
        
        // Process each record
        for (Map<String, Object> bodyData : records) {
            if (bodyData == null) continue; 
            
            String recordId = (String) bodyData.get('id');
            Boolean isCreate = (recordId == null || String.isBlank(recordId));
            HealthCondition mh;
            
            if (isCreate) {
                mh = new HealthCondition();
                toInsert.add(mh);
                insertIndexToData.put(insertIndex++, bodyData);
            } else {
                mh = historyMap.get(recordId);
                if (mh == null) {
                    ResponseWrapper resp = new ResponseWrapper();
                    resp.success = false;
                    resp.message = 'Medical History record not found: ' + recordId;
                    resp.errorCode = 'RECORD_NOT_FOUND';
                    resp.recordId = recordId;
                    resp.objectType = 'HealthCondition';
                    resp.recordData = bodyData;
                    responses.add(resp);
                    continue;
                }
                toUpdate.add(mh);
                updateIdToData.put(recordId, bodyData);
            }
            
            if (bodyData.containsKey('medicalProblem') && bodyData.get('medicalProblem') != null) {
                mh.ProblemName = (String) bodyData.get('medicalProblem');
            }
            
            if (bodyData.containsKey('onsetDate') && bodyData.get('onsetDate') != null) {
                Date onsetDate = parseDate(bodyData.get('onsetDate'));
                if (onsetDate != null) {
                    mh.OnsetStartDateTime = DateTime.newInstance(onsetDate.year(), onsetDate.month(), onsetDate.day());
                }
            }
            
            if (bodyData.containsKey('note') && bodyData.get('note') != null) {
                mh.ProblemDescription = (String) bodyData.get('note');
            }
            if (bodyData.containsKey('status') && bodyData.get('status') != null) {
                mh.ConditionStatus = (String)bodyData.get('status');
            }
            
            if (isCreate && bodyData.containsKey('accountId') && bodyData.get('accountId') != null) {
                mh.PatientId = (String) bodyData.get('accountId');
            }
        }
        
        // Perform UPDATE
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                HealthCondition mh = toUpdate[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.recordId = mh != null ? mh.Id : null; 
                resp.objectType = 'HealthCondition';
                resp.recordData = mh != null ? updateIdToData.get(mh.Id) : null;
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Medical History record updated successfully';
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to update medical history: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                    system.debug('resp.message--> update medical history: ' + resp.message);
                }
                responses.add(resp);
            }
        }
        
        // Perform INSERT
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.objectType = 'HealthCondition';
                resp.recordData = insertIndexToData.get(i);
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Medical History record created successfully';
                    resp.recordId = sr.getId();
                    if (resp.recordData != null) {
                        resp.recordData.put('id', sr.getId());
                    }
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to create medical history: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                    system.debug('resp.message--> create medical history: ' + resp.message);
                }
                responses.add(resp);
            }
        }
        
        return responses;
    }
    
    /* ============================================================================
BULK UPDATE ALLERGY - Using AllergyIntolerance Object
============================================================================ */
    private static List<ResponseWrapper> bulkUpdateAllergy(List<Map<String, Object>> records) {
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        if (records == null || records.isEmpty()) {
            return responses;
        }
        
        Set<String> updateIds = new Set<String>();
        
        for (Map<String, Object> record : records) {
            if (record == null) continue;
            
            String recordId = (String)record.get('id');
            if (!String.isBlank(recordId)) {
                updateIds.add(recordId);
            }
        }
        
        Map<String, AllergyIntolerance> allergyMap = new Map<String, AllergyIntolerance>();
        if (!updateIds.isEmpty()) {
            AllergyIntolerance[] existingRecs = [
                SELECT Id, Name, Allergy_Name__c, Severity, OnsetStartDateTime, 
                Note__c, PatientId, Status, Reaction__c,Combine_allergy_and_Generic__c
                FROM AllergyIntolerance
                WHERE Id IN :updateIds
            ];
            
            for (AllergyIntolerance a : existingRecs) {
                if (a != null && a.Id != null) { 
                    allergyMap.put(a.Id, a);
                }
            }
        }
        
        List<AllergyIntolerance> toUpdate = new List<AllergyIntolerance>();
        List<AllergyIntolerance> toInsert = new List<AllergyIntolerance>();
        Map<Integer, Map<String, Object>> insertIndexToData = new Map<Integer, Map<String, Object>>();
        Map<String, Map<String, Object>> updateIdToData = new Map<String, Map<String, Object>>();
        Integer insertIndex = 0;
        
        for (Map<String, Object> bodyData : records) {
            if (bodyData == null) continue; 
            
            String recordId = (String)bodyData.get('id');
            Boolean isCreate = (recordId == null || String.isBlank(recordId));   
            AllergyIntolerance allergy;
            
            if (isCreate) {
                allergy = new AllergyIntolerance();
                toInsert.add(allergy);
                insertIndexToData.put(insertIndex++, bodyData);
            } else {
                allergy = allergyMap.get(recordId);
                
                if (allergy == null) {
                    ResponseWrapper resp = new ResponseWrapper();
                    resp.success = false;
                    resp.message = 'Allergy record not found: ' + recordId;
                    resp.errorCode = 'RECORD_NOT_FOUND';
                    resp.recordId = recordId;
                    resp.objectType = 'AllergyIntolerance';
                    resp.recordData = bodyData;
                    responses.add(resp);
                    continue;
                }
                
                toUpdate.add(allergy);
                updateIdToData.put(recordId, bodyData);
            }
            
            if (bodyData.containsKey('name') && bodyData.get('name') != null) 
                allergy.Allergy_Name__c = (String)bodyData.get('name');
            allergy.Combine_allergy_and_Generic__c = (String)bodyData.get('name');
            
            if (bodyData.containsKey('severity') && bodyData.get('severity') != null) 
                allergy.Severity = (String)bodyData.get('severity');
            
            if (bodyData.containsKey('reaction') && bodyData.get('reaction') != null) 
                allergy.Reaction__c = (String)bodyData.get('reaction');
            if (bodyData.containsKey('status') && bodyData.get('status') != null) 
                allergy.Status = (String)bodyData.get('status');
            if (bodyData.containsKey('onsetDate') && bodyData.get('onsetDate') != null) {
                Date onsetDate = parseDate(bodyData.get('onsetDate'));
                if (onsetDate != null) {
                    allergy.OnsetStartDateTime = DateTime.newInstance(onsetDate.year(), onsetDate.month(), onsetDate.day());
                }
            }
            
            if (bodyData.containsKey('note') && bodyData.get('note') != null) 
                allergy.Note__c = (String)bodyData.get('note');
            
            if (isCreate && bodyData.containsKey('accountId') && bodyData.get('accountId') != null) {
                allergy.PatientId = (String)bodyData.get('accountId');
            }
        }   
        // Perform UPDATE
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                AllergyIntolerance allergy = toUpdate[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.recordId = allergy != null ? allergy.Id : null;
                resp.objectType = 'AllergyIntolerance';
                resp.recordData = allergy != null ? updateIdToData.get(allergy.Id) : null;
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Allergy record updated successfully';
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to update allergy: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                }
                responses.add(resp);
            }
        }
        
        // Perform INSERT
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
            
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.objectType = 'AllergyIntolerance';
                resp.recordData = insertIndexToData.get(i);
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Allergy record created successfully';
                    resp.recordId = sr.getId();
                    if (resp.recordData != null) {
                        resp.recordData.put('id', sr.getId());
                    }
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to create allergy: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                }
                
                responses.add(resp);
            }
        }  
        
        return responses;
    }
    
    /* ============================================================================
MEDICATION LOOKUP / CREATE / UPDATE HELPER (FIXED)
============================================================================ */
    public static Map<String, String> medicationNameCache = new Map<String, String>();
    
    public static Map<String, String> findOrCreateMedications(
        Set<String> medicationNames,
        Map<String, String> nameToIdProvided
    ) {
        Map<String, String> nameToIdMap = new Map<String, String>();
        
        if (medicationNames == null || medicationNames.isEmpty()) {
            return nameToIdMap;
        }
        
        /* ------------------------------
Normalize input
------------------------------ */
        Map<String, String> normalizedToOriginal = new Map<String, String>();
        Set<String> normalizedNames = new Set<String>();
        
        for (String name : medicationNames) {
            if (String.isBlank(name)) continue;
            String normalized = name.trim().toLowerCase();
            normalizedNames.add(normalized);
            normalizedToOriginal.put(normalized, name.trim());
        }
        
        Set<String> uncachedNames = new Set<String>();
        List<Medication> medicationsToUpdate = new List<Medication>();
        
        /* ------------------------------
STEP 1: Handle provided medication IDs
------------------------------ */
        if (nameToIdProvided != null && !nameToIdProvided.isEmpty()) {
            
            Set<Id> providedIds = new Set<Id>();
            Map<String, Id> normalizedNameToId = new Map<String, Id>();
            
            for (String originalName : nameToIdProvided.keySet()) {
                if (String.isBlank(originalName)) continue;
                
                String normalized = originalName.trim().toLowerCase();
                String idVal = nameToIdProvided.get(originalName);
                
                if (!String.isBlank(idVal)) {
                    providedIds.add((Id) idVal);
                    normalizedNameToId.put(normalized, (Id) idVal);
                }
            }
            
            if (!providedIds.isEmpty()) {
                Map<Id, Medication> existingById =
                    new Map<Id, Medication>([
                        SELECT Id, Name
                        FROM Medication
                        WHERE Id IN :providedIds
                    ]);
                
                for (String normalized : normalizedNameToId.keySet()) {
                    Id medId = normalizedNameToId.get(normalized);
                    
                    if (!existingById.containsKey(medId)) {
                        uncachedNames.add(normalized);
                        continue;
                    }
                    
                    Medication existing = existingById.get(medId);
                    String newName = normalizedToOriginal.get(normalized);
                    
                    nameToIdMap.put(normalized, medId);
                    
                    String existingLower = existing.Name.trim().toLowerCase();
                    String newLower = newName.trim().toLowerCase();
                    
                    if (existingLower != newLower) {
                        medicationsToUpdate.add(
                            new Medication(
                                Id = medId,
                                Name = newName
                            )
                        );
                    }
                }
            }
        }
        
        /* ------------------------------
STEP 2: Update renamed medications
------------------------------ */
        if (!medicationsToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults =
                Database.update(medicationsToUpdate, false);
            
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (updateResults[i].isSuccess()) {
                    Medication m = medicationsToUpdate[i];
                    medicationNameCache.put(
                        m.Name.trim().toLowerCase(),
                        m.Id
                    );
                }
            }
        }
        
        /* ------------------------------
STEP 3: Cache / unresolved names
------------------------------ */
        for (String normalized : normalizedNames) {
            if (nameToIdMap.containsKey(normalized)) continue;
            
            if (medicationNameCache.containsKey(normalized)) {
                nameToIdMap.put(normalized, medicationNameCache.get(normalized));
            } else {
                uncachedNames.add(normalized);
            }
        }
        
        if (uncachedNames.isEmpty()) {
            return nameToIdMap;
        }
        
        /* ------------------------------
STEP 4: Query existing medications
------------------------------ */
        List<String> conditions = new List<String>();
        for (String name : uncachedNames) {
            conditions.add(
                'Name LIKE \'%' + String.escapeSingleQuotes(name) + '%\''
            );
        }
        
        String soql =
            'SELECT Id, Name FROM Medication WHERE ' +
            String.join(conditions, ' OR ') +
            ' LIMIT 10000';
        
        List<Medication> existingMeds = Database.query(soql);
        
        Map<String, Medication> exact = new Map<String, Medication>();
        Map<String, Medication> starts = new Map<String, Medication>();
        Map<String, Medication> contains = new Map<String, Medication>();
        
        for (Medication med : existingMeds) {
            String medLower = med.Name.trim().toLowerCase();
            
            for (String search : uncachedNames) {
                if (exact.containsKey(search)) continue;
                
                if (medLower == search) {
                    exact.put(search, med);
                } else if (medLower.startsWith(search)) {
                    starts.put(search, med);
                } else if (medLower.contains(search)) {
                    contains.put(search, med);
                }
            }
        }
        
        for (String search : uncachedNames) {
            Medication match =
                exact.containsKey(search) ? exact.get(search) :
            starts.containsKey(search) ? starts.get(search) :
            contains.get(search);
            
            if (match != null) {
                nameToIdMap.put(search, match.Id);
                medicationNameCache.put(search, match.Id);
            }
        }
        
        /* ------------------------------
STEP 5: Create new medications
------------------------------ */
        List<Medication> toInsert = new List<Medication>();
        Map<Integer, String> indexToName = new Map<Integer, String>();
        Integer idx = 0;
        
        for (String normalized : uncachedNames) {
            if (!nameToIdMap.containsKey(normalized)) {
                toInsert.add(
                    new Medication(
                        Name = normalizedToOriginal.get(normalized)
                    )
                );
                indexToName.put(idx++, normalized);
            }
        }
        
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] insertResults =
                Database.insert(toInsert, false);
            
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (insertResults[i].isSuccess()) {
                    String normalized = indexToName.get(i);
                    nameToIdMap.put(normalized, insertResults[i].getId());
                    medicationNameCache.put(normalized, insertResults[i].getId());
                }
            }
        }
        
        return nameToIdMap;
    }
    
    /* Backward compatibility */
    public static Map<String, String> findOrCreateMedications(Set<String> medicationNames) {
        return findOrCreateMedications(medicationNames, null);
    }
    
    /* ============================================================================
BULK UPDATE MEDICATION
============================================================================ */
    private static List<ResponseWrapper> bulkUpdateMedication(List<Map<String, Object>> records) {
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        if (records == null || records.isEmpty()) {
            return responses;
        }
        
        Set<String> medicationNamesToFind = new Set<String>();
        Map<String, String> nameToProvidedId = new Map<String, String>();
        
        for (Map<String, Object> record : records) {
            if (record == null) continue;
            
            String medName = (String) record.get('medication');
            String medId = (String) record.get('medicationid');
            
            if (!String.isBlank(medName)) {
                String normalizedName = medName.trim().toLowerCase();
                medicationNamesToFind.add(medName.trim());
                if (!String.isBlank(medId)) {
                    nameToProvidedId.put(normalizedName, medId);
                }
            }
        }
        Map<String, String> medNameToIdMap = findOrCreateMedications(medicationNamesToFind, nameToProvidedId);
        Set<String> updateIds = new Set<String>();
        for (Map<String, Object> record : records) {
            if (record == null) continue;
            String recordId = (String) record.get('id');
            if (!String.isBlank(recordId)) {
                updateIds.add(recordId);
            }
        }
        
        Map<String, MedicationStatement> medMap = new Map<String, MedicationStatement>();
        if (!updateIds.isEmpty()) {
            for (MedicationStatement med : [
                SELECT Id, Name, Dose__c, Frequency__c, Reason__c, PatientId,
                Comments__c, Status, StartDateTime, EndDateTime, Patient__c, MedicationId
                FROM MedicationStatement
                WHERE Id IN :updateIds
            ]) {
                medMap.put(med.Id, med);
            }
        }
        
        List<MedicationStatement> toUpdate = new List<MedicationStatement>();
        List<MedicationStatement> toInsert = new List<MedicationStatement>();
        Map<Integer, Map<String, Object>> insertIndexToData = new Map<Integer, Map<String, Object>>();
        Map<String, Map<String, Object>> updateIdToData = new Map<String, Map<String, Object>>();
        Integer insertIndex = 0;
        
        // Process each record
        for (Map<String, Object> bodyData : records) {
            if (bodyData == null) continue;
            
            String recordId = (String) bodyData.get('id');
            Boolean isCreate = (recordId == null || String.isBlank(recordId));
            MedicationStatement med;
            
            if (isCreate) {
                med = new MedicationStatement();
                toInsert.add(med);
                insertIndexToData.put(insertIndex++, bodyData);
            } else {
                med = medMap.get(recordId);
                if (med == null) {
                    ResponseWrapper resp = new ResponseWrapper();
                    resp.success = false;
                    resp.message = 'Medication record not found: ' + recordId;
                    resp.errorCode = 'RECORD_NOT_FOUND';
                    resp.recordId = recordId;
                    resp.objectType = 'MedicationStatement';
                    resp.recordData = bodyData;
                    responses.add(resp);
                    continue;
                }
                toUpdate.add(med);
                updateIdToData.put(recordId, bodyData);
            }
            
            // Handle medication ID assignment
            if (bodyData.containsKey('medication') && bodyData.get('medication') != null) {
                String medName = ((String) bodyData.get('medication')).trim().toLowerCase();
                
                if (medNameToIdMap.containsKey(medName)) {
                    med.MedicationId = medNameToIdMap.get(medName);
                }
            }
            
            if (bodyData != null && med.MedicationId != null) {
                bodyData.put('medicationid', med.MedicationId);
            }
            
            if (bodyData.containsKey('contactId') && bodyData.get('contactId') != null) {
                med.Patient__c = (String) bodyData.get('contactId');
            }
            if (isCreate && bodyData.containsKey('accountId') && bodyData.get('accountId') != null) {
                med.PatientId = (String) bodyData.get('accountId');
            }
            
            if (bodyData.containsKey('dosage') && bodyData.get('dosage') != null) {
                med.Dose__c = (String) bodyData.get('dosage');
            }
            if (bodyData.containsKey('frequency') && bodyData.get('frequency') != null) {
                med.Frequency__c = (String) bodyData.get('frequency');
            }
            if (bodyData.containsKey('reason') && bodyData.get('reason') != null) {
                med.Reason__c = (String) bodyData.get('reason');
            }
            if (bodyData.containsKey('notes') && bodyData.get('notes') != null) {
                med.Comments__c = (String) bodyData.get('notes');
            }
            if (bodyData.containsKey('status') && bodyData.get('status') != null) {
                med.Status = (String) bodyData.get('status');
            }
            if (bodyData.containsKey('startDate') && bodyData.get('startDate') != null) {
                med.StartDateTime = parseDatetime(bodyData.get('startDate'));
            }
            if (bodyData.containsKey('endDate') && bodyData.get('endDate') != null) {
                med.EndDateTime = parseDatetime(bodyData.get('endDate'));
            }
        } 
        
        // Perform UPDATE operations
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                MedicationStatement med = toUpdate[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.recordId = med != null ? med.Id : null; 
                resp.objectType = 'MedicationStatement';
                resp.recordData = med != null ? updateIdToData.get(med.Id) : null;
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Medication record updated successfully';
                } else {
                    resp.success = false;
                    String errorMsg = 'Unknown error';
                    String errorCode = 'DML_ERROR';
                    
                    if (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) {
                        Database.Error err = sr.getErrors()[0];
                        errorMsg = err.getMessage();
                        errorCode = String.valueOf(err.getStatusCode());
                    }
                    
                    resp.message = 'Failed to update medication: ' + errorMsg;
                    resp.errorCode = errorCode;
                    resp.errorDetails = errorMsg;
                    
                    system.debug('  resp.message--> update medication'+  resp.message);
                }
                responses.add(resp);
            }
        }
        
        if (!toInsert.isEmpty()) {
            System.debug('Attempting to insert ' + toInsert.size() + ' medication records');
            Database.SaveResult[] results = Database.insert(toInsert, false);
            
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                MedicationStatement insertedMed = toInsert[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.objectType = 'MedicationStatement';
                resp.recordData = insertIndexToData.get(i);
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Medication record created successfully';
                    resp.recordId = sr.getId();
                    if (resp.recordData != null) {
                        resp.recordData.put('id', sr.getId());
                    }
                } else {
                    resp.success = false;
                    String errorMsg = 'Unknown error';
                    String errorCode = 'DML_ERROR';
                    
                    if (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) {
                        Database.Error err = sr.getErrors()[0];
                        errorMsg = err.getMessage();
                        errorCode = String.valueOf(err.getStatusCode());
                    }
                    resp.message = 'Failed to create medication: ' + errorMsg;
                    resp.errorCode = errorCode;
                    resp.errorDetails = errorMsg;
                    resp.recordId = null; 
                    system.debug('  resp.message--> create medication'+  resp.message);
                }
                responses.add(resp);
            }
        }
        return responses;
    }
    
    /* ============================================================================
BULK UPDATE INSURANCE PLAN
============================================================================ */
    private static List<ResponseWrapper> bulkUpdateInsurancePlan(List<Map<String, Object>> records) {
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        if (records == null || records.isEmpty()) {
            return responses;
        }
        
        Set<String> updateIds = new Set<String>();
        for (Map<String, Object> rec : records) {
            if (rec == null) continue; 
            String idVal = (String) rec.get('id');
            if (!String.isBlank(idVal)) updateIds.add(idVal);
        }
        
        // Query existing plans
        Map<String, MemberPlan> planMap = new Map<String, MemberPlan>();
        if (!updateIds.isEmpty()) {
            List<MemberPlan> existingPlans = [
                SELECT Id, Name, medicalcoverage__Payer_Name__c, GroupNumber,
                MemberNumber, medicalcoverage__Subscriber_First_Name__c,
                medicalcoverage__Subscriber_Last_Name__c,
                medicalcoverage__Subscriber_Birth_Date__c,
                RelationshipToSubscriber, PrimarySecondaryTertiary,
                MemberId
                FROM MemberPlan
                WHERE Id IN :updateIds
            ];
            for (MemberPlan p : existingPlans) {
                if (p != null && p.Id != null) { 
                    planMap.put(p.Id, p);
                }
            }
        }
        
        List<MemberPlan> toUpdate = new List<MemberPlan>();
        List<MemberPlan> toInsert = new List<MemberPlan>();
        Map<Integer, Map<String, Object>> insertIndexToData = new Map<Integer, Map<String, Object>>();
        Map<String, Map<String, Object>> updateIdToData = new Map<String, Map<String, Object>>();
        
        // Process each record
        for (Map<String, Object> bodyData : records) {
            if (bodyData == null) continue; 
            
            String idVal = (String) bodyData.get('id');
            Boolean isCreate = (idVal == null || String.isBlank(idVal));
            MemberPlan plan;
            
            if (isCreate) {
                plan = new MemberPlan();
                toInsert.add(plan);
                insertIndexToData.put(toInsert.size() - 1, bodyData);
            } else {
                plan = planMap.get(idVal);
                if (plan == null) {
                    ResponseWrapper resp = new ResponseWrapper();
                    resp.success = false;
                    resp.message = 'Insurance Plan record not found: ' + idVal;
                    resp.errorCode = 'RECORD_NOT_FOUND';
                    resp.recordId = idVal;
                    resp.objectType = 'MemberPlan';
                    resp.recordData = bodyData;
                    responses.add(resp);
                    continue;
                }
                toUpdate.add(plan);
                updateIdToData.put(idVal, bodyData);
            }
            if (bodyData.containsKey('accountId') && bodyData.get('accountId') != null){
                plan.MemberId = (String) bodyData.get('accountId');
            }
            if (bodyData.containsKey('Name') && bodyData.get('Name') != null){
                plan.Name = (String) bodyData.get('Name');
            }
            if (bodyData.containsKey('providerName') && bodyData.get('providerName') != null) 
                plan.Name = (String) bodyData.get('providerName');
            if (bodyData.containsKey('providerName') && bodyData.get('providerName') != null) 
                plan.medicalcoverage__Payer_Name__c = (String) bodyData.get('providerName');
            if (bodyData.containsKey('GroupNumber') && bodyData.get('GroupNumber') != null) 
                plan.GroupNumber = (String) bodyData.get('GroupNumber');
            if (bodyData.containsKey('memberNumber') && bodyData.get('memberNumber') != null) 
                plan.MemberNumber = (String) bodyData.get('memberNumber');
            if (bodyData.containsKey('Subscriber_First_Name') && bodyData.get('Subscriber_First_Name') != null) 
                plan.medicalcoverage__Subscriber_First_Name__c = (String) bodyData.get('Subscriber_First_Name');
            if (bodyData.containsKey('Subscriber_Last_Name') && bodyData.get('Subscriber_Last_Name') != null) 
                plan.medicalcoverage__Subscriber_Last_Name__c = (String) bodyData.get('Subscriber_Last_Name');
            if (bodyData.containsKey('Subscriber_Birth_Date') && bodyData.get('Subscriber_Birth_Date') != null) 
                plan.medicalcoverage__Subscriber_Birth_Date__c = parseDate(bodyData.get('Subscriber_Birth_Date'));
            if (bodyData.containsKey('RelationshipToSubscriber') && bodyData.get('RelationshipToSubscriber') != null) 
                plan.RelationshipToSubscriber = (String) bodyData.get('RelationshipToSubscriber');
            if (bodyData.containsKey('PrimarySecondaryTertiary') && bodyData.get('PrimarySecondaryTertiary') != null) 
                plan.PrimarySecondaryTertiary = (String) bodyData.get('PrimarySecondaryTertiary');
        }
        
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                MemberPlan plan = toUpdate[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.recordId = plan != null ? plan.Id : null; 
                resp.objectType = 'MemberPlan';
                resp.recordData = plan != null ? updateIdToData.get(plan.Id) : null;
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Insurance Plan updated successfully';
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to update insurance plan: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                    system.debug('  resp.message--> update insurance plan'+  resp.message);
                    
                }
                responses.add(resp);
            }
        }
        
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
            
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.objectType = 'MemberPlan';
                resp.recordData = insertIndexToData.containsKey(i)
                    ? insertIndexToData.get(i)
                    : new Map<String, Object>();
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Insurance Plan created successfully';
                    resp.recordId = sr.getId();
                    
                    // Ensure non-null before updating
                    if (resp.recordData == null) resp.recordData = new Map<String, Object>();
                    resp.recordData.put('id', sr.getId());
                    
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to create insurance plan: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                    system.debug('  resp.message--> create insurance plan'+  resp.message);
                    
                }
                
                responses.add(resp);
            }
        }
        
        return responses;
    }

// For contact Record type
private static Id getContactRecordTypeId() {
    List<RecordType> rt = [
         SELECT Id, DeveloperName FROM RecordType  
        WHERE SObjectType = 'Contact' 
        AND IsActive = true 
        AND DeveloperName = 'Related_Person'
        LIMIT 1
    ];
    return rt.isEmpty() ? null : rt[0].Id;
}
    
    /* ============================================================================
STATE CODE MAPPING UTILITY - BIDIRECTIONAL
============================================================================ */
    private static final Map<String, String> STATE_NAME_TO_CODE = new Map<String, String>{
        'alabama' => 'AL', 'alaska' => 'AK', 'arizona' => 'AZ', 'arkansas' => 'AR',
            'california' => 'CA', 'colorado' => 'CO', 'connecticut' => 'CT', 'delaware' => 'DE',
            'florida' => 'FL', 'georgia' => 'GA', 'hawaii' => 'HI', 'idaho' => 'ID',
            'illinois' => 'IL', 'indiana' => 'IN', 'iowa' => 'IA', 'kansas' => 'KS',
            'kentucky' => 'KY', 'louisiana' => 'LA', 'maine' => 'ME', 'maryland' => 'MD',
            'massachusetts' => 'MA', 'michigan' => 'MI', 'minnesota' => 'MN', 'mississippi' => 'MS',
            'missouri' => 'MO', 'montana' => 'MT', 'nebraska' => 'NE', 'nevada' => 'NV',
            'new hampshire' => 'NH', 'new jersey' => 'NJ', 'new mexico' => 'NM', 'new york' => 'NY',
            'north carolina' => 'NC', 'north dakota' => 'ND', 'ohio' => 'OH', 'oklahoma' => 'OK',
            'oregon' => 'OR', 'pennsylvania' => 'PA', 'rhode island' => 'RI', 'south carolina' => 'SC',
            'south dakota' => 'SD', 'tennessee' => 'TN', 'texas' => 'TX', 'utah' => 'UT',
            'vermont' => 'VT', 'virginia' => 'VA', 'washington' => 'WA', 'west virginia' => 'WV',
            'wisconsin' => 'WI', 'wyoming' => 'WY', 'district of columbia' => 'DC',
            'american samoa' => 'AS', 'guam' => 'GU', 'northern mariana islands' => 'MP', 'puerto rico' => 'PR',
            'palau' => 'PW', 'federated micronesia' => 'FM', 'marshall islands' => 'MH',
            'armed forces americas' => 'AA', 'armed forces europe' => 'AE', 'armed forces pacific' => 'AP',
            'virgin islands' => 'VI', 'u.s. virgin islands' => 'VI', 'us virgin islands' => 'VI'
            };
                
                private static Map<String, String> stateCodeToNameCache;
    
    // Dynamic Build the State code name
    private static Map<String, String> getStateCodeToNameMap() {
        if (stateCodeToNameCache != null) {
            return stateCodeToNameCache;
        }
        
        stateCodeToNameCache = new Map<String, String>();
        
        for (String stateName : STATE_NAME_TO_CODE.keySet()) {
            String stateCode = STATE_NAME_TO_CODE.get(stateName);
            String displayName = capitalizeWords(stateName);
            stateCodeToNameCache.put(stateCode, displayName);
        }
        
        return stateCodeToNameCache;
    }
    
    private static String capitalizeWords(String input) {
        if (String.isBlank(input)) {
            return input;
        }
        
        List<String> words = input.split(' ');
        List<String> capitalizedWords = new List<String>();
        
        for (String word : words) {
            if (String.isNotBlank(word)) {
                capitalizedWords.add(word.substring(0, 1).toUpperCase() + word.substring(1));
            }
        }
        
        return String.join(capitalizedWords, ' ');
    }
    
    /**
* Converts state code to full state name
*/
    public static String getStateName(String stateCode) {
        if (String.isBlank(stateCode)) {
            return null;
        }
        
        String upperCode = stateCode.trim().toUpperCase();
        Map<String, String> codeToName = getStateCodeToNameMap();
        
        if (codeToName.containsKey(upperCode)) {
            return codeToName.get(upperCode);
        }
        
        return stateCode;
    }
    
    private static String getStateCode(String stateInput) {
        if (String.isBlank(stateInput)) {
            return null;
        }
        
        String trimmedInput = stateInput.trim();
        if (trimmedInput.length() == 2) {
            return trimmedInput.toUpperCase();
        }
        
        String normalizedInput = trimmedInput.toLowerCase();
        if (STATE_NAME_TO_CODE.containsKey(normalizedInput)) {
            return STATE_NAME_TO_CODE.get(normalizedInput);
        }
        
        return trimmedInput.toUpperCase();
    }
    
    /* ============================================================================
BULK UPDATE HEALTHCARE FACILITY
============================================================================ */
    private static List<ResponseWrapper> bulkUpdateHealthcareFacility(List<Map<String, Object>> records) {
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        if (records == null || records.isEmpty()) {
            return responses;
        }
        Set<String> updateIds = new Set<String>();
        for (Map<String, Object> rec : records) {
            if (rec == null) continue; 
            
            String idVal = (String) rec.get('id');
            if (!String.isBlank(idVal)) updateIds.add(idVal);
        }
        
        // Query existing facilities
        Map<String, HealthcareFacility> facilityMap = new Map<String, HealthcareFacility>();
        if (!updateIds.isEmpty()) {
            List<HealthcareFacility> existingRecs = [
                SELECT Id, Name, AccountId, 
                Phone__c, Email__c, Facility_type__c,Fax_Number__c,Website__c,
                Mailing_Address__c
                FROM HealthcareFacility
                WHERE Id IN :updateIds
            ];
            for (HealthcareFacility f : existingRecs) {
                if (f != null && f.Id != null) { 
                    facilityMap.put(f.Id, f);
                }
            }
        }
        
        List<HealthcareFacility> toUpdate = new List<HealthcareFacility>();
        List<HealthcareFacility> toInsert = new List<HealthcareFacility>();
        Map<Integer, Map<String, Object>> insertIndexToData = new Map<Integer, Map<String, Object>>();
        Map<String, Map<String, Object>> updateIdToData = new Map<String, Map<String, Object>>();
        Integer insertIndex = 0;
        
        // Process each record
        for (Map<String, Object> bodyData : records) {
            if (bodyData == null) continue; 
            
            String idVal = (String) bodyData.get('id');
            Boolean isCreate = String.isBlank(idVal);
            HealthcareFacility fac;
            
            if (isCreate) {
                fac = new HealthcareFacility();
                toInsert.add(fac);
                insertIndexToData.put(insertIndex++, bodyData);
            } else {
                fac = facilityMap.get(idVal);
                if (fac == null) {
                    ResponseWrapper resp = new ResponseWrapper();
                    resp.success = false;
                    resp.message = 'Healthcare Facility record not found: ' + idVal;
                    resp.errorCode = 'RECORD_NOT_FOUND';
                    resp.recordId = idVal;
                    resp.objectType = 'HealthcareFacility';
                    resp.recordData = bodyData;
                    responses.add(resp);
                    continue;
                }
                toUpdate.add(fac);
                updateIdToData.put(idVal, bodyData);
            }
            
            
            if (bodyData.containsKey('facilityName') && bodyData.get('facilityName') != null) 
                fac.Name = (String) bodyData.get('facilityName');
            if (bodyData.containsKey('name') && bodyData.get('name') != null) 
                fac.Name = (String) bodyData.get('name');
            if (bodyData.containsKey('phoneNumber') && bodyData.get('phoneNumber') != null) 
                fac.Phone__c = (String) bodyData.get('phoneNumber');
            if (bodyData.containsKey('email') && bodyData.get('email') != null) 
                fac.Email__c = (String) bodyData.get('email');
            if (bodyData.containsKey('facilityType') && bodyData.get('facilityType') != null) 
                fac.Facility_type__c = (String) bodyData.get('facilityType');
            if (bodyData.containsKey('accountId') && bodyData.get('accountId') != null) 
                fac.AccountId = (String) bodyData.get('accountId');
            if (bodyData.containsKey('faxNumber') && bodyData.get('faxNumber') != null) 
                fac.Fax_Number__c = (String) bodyData.get('faxNumber');
            if (bodyData.containsKey('website') && bodyData.get('website') != null) 
                fac.Website__c = (String) bodyData.get('website');
            if (bodyData.containsKey('address') && bodyData.get('address') != null) {
                Map<String, Object> addr = (Map<String, Object>) bodyData.get('address');
                if (addr != null) {
                    if (addr.containsKey('street')) 
                        fac.Mailing_Address__Street__s = (String) addr.get('street');
                    
                    if (addr.containsKey('city')) 
                        fac.Mailing_Address__City__s = (String) addr.get('city');
                    
                    if (addr.containsKey('state')) {
                        String stateInput = (String) addr.get('state');
                        fac.Mailing_Address__StateCode__s = getStateCode(stateInput);
                    }
                    
                    if (addr.containsKey('zipCode')) 
                        fac.Mailing_Address__PostalCode__s = (String) addr.get('zipCode');
                    
                    if (addr.containsKey('country')) 
                        fac.Mailing_Address__CountryCode__s = (String) addr.get('country');
                }
            }
        }
        
        // Bulk UPDATE
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                HealthcareFacility rec = toUpdate[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.recordId = rec != null ? rec.Id : null; 
                resp.objectType = 'HealthcareFacility';
                resp.recordData = rec != null ? updateIdToData.get(rec.Id) : null;
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Healthcare Facility updated successfully';
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) ? sr.getErrors()[0].getMessage() : 'Unknown error';
                    resp.message = 'Failed to update Healthcare Facility: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                    System.debug('resp.message--> update Healthcare Facility: ' + resp.message);
                }
                responses.add(resp);
            }
        }
        
        // Bulk INSERT
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.objectType = 'HealthcareFacility';
                resp.recordData = insertIndexToData.get(i);
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Healthcare Facility created successfully';
                    resp.recordId = sr.getId();
                    // Update the data with new ID
                    if (resp.recordData != null) {
                        resp.recordData.put('id', sr.getId());
                    }
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to create Healthcare Facility: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                }
                responses.add(resp);
            }
        }
        
        return responses;
    }
    /* ============================================================================
BULK UPDATE HEALTHCARE PROFESSIONAL
============================================================================ */
    private static List<ResponseWrapper> bulkUpdateHealthcareProfessional(List<Map<String, Object>> records) {
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        if (records == null || records.isEmpty()) {
            return responses;
        }
        Set<String> updateIds = new Set<String>();
        for (Map<String, Object> rec : records) {
            if (rec == null) continue;
            
            String idVal = (String) rec.get('id');
            if (!String.isBlank(idVal)) updateIds.add(idVal);
        }
        
        // Query existing professionals
        Map<String, HealthcarePractitionerFacility> professionalMap = new Map<String, HealthcarePractitionerFacility>();
        if (!updateIds.isEmpty()) {
            List<HealthcarePractitionerFacility> existingRecs = [
                SELECT Id, Name, AccountId, PractitionerId, Practitioner.Name,Fax_Number__c,Website__c,
                Phone__c, Email__c,Address__c,Specialty__c
                FROM HealthcarePractitionerFacility
                WHERE Id IN :updateIds
            ];
            for (HealthcarePractitionerFacility p : existingRecs) {
                if (p != null && p.Id != null) { 
                    professionalMap.put(p.Id, p);
                }
            }
        }
        
        List<HealthcarePractitionerFacility> toUpdate = new List<HealthcarePractitionerFacility>();
        List<HealthcarePractitionerFacility> toInsert = new List<HealthcarePractitionerFacility>();
        Map<Integer, Map<String, Object>> insertIndexToData = new Map<Integer, Map<String, Object>>();
        Map<String, Map<String, Object>> updateIdToData = new Map<String, Map<String, Object>>();
        Integer insertIndex = 0;
        
        for (Map<String, Object> bodyData : records) {
            if (bodyData == null) continue; 
            
            String idVal = (String) bodyData.get('id');
            Boolean isCreate = String.isBlank(idVal);
            HealthcarePractitionerFacility pro;
            
            if (isCreate) {
                pro = new HealthcarePractitionerFacility();
                toInsert.add(pro);
                insertIndexToData.put(insertIndex++, bodyData);
            } else {
                pro = professionalMap.get(idVal);
                if (pro == null) {
                    ResponseWrapper resp = new ResponseWrapper();
                    resp.success = false;
                    resp.message = 'Healthcare Professional record not found: ' + idVal;
                    resp.errorCode = 'RECORD_NOT_FOUND';
                    resp.recordId = idVal;
                    resp.objectType = 'HealthcarePractitionerFacility';
                    resp.recordData = bodyData;
                    responses.add(resp);
                    continue;
                }
                toUpdate.add(pro);
                updateIdToData.put(idVal, bodyData);
            }
            
            
            if (bodyData.containsKey('name') && bodyData.get('name') != null) 
                pro.Name = (String) bodyData.get('name');
            if (bodyData.containsKey('professionalName') && bodyData.get('professionalName') != null) 
                pro.Name = (String) bodyData.get('professionalName');
            if (bodyData.containsKey('specialty') && bodyData.get('specialty') != null) 
                pro.Specialty__c = (String) bodyData.get('specialty');
            if (bodyData.containsKey('phoneNumber') && bodyData.get('phoneNumber') != null) 
                pro.Phone__c = (String) bodyData.get('phoneNumber');
            if (bodyData.containsKey('email') && bodyData.get('email') != null) 
                pro.Email__c = (String) bodyData.get('email');
            if (bodyData.containsKey('faxNumber') && bodyData.get('faxNumber') != null) 
                pro.Fax_Number__c = (String) bodyData.get('faxNumber');
            if (bodyData.containsKey('website') && bodyData.get('website') != null) 
                pro.Website__c = (String) bodyData.get('website');
            if (bodyData.containsKey('accountId') && bodyData.get('accountId') != null) 
                pro.AccountId = (String) bodyData.get('accountId');
            
            if (bodyData.containsKey('address') && bodyData.get('address') != null) {
                Map<String, Object> addr = (Map<String, Object>) bodyData.get('address');
                if (addr != null) {
                    if (addr.containsKey('street')) 
                        pro.Address__Street__s = (String) addr.get('street');
                    if (addr.containsKey('city')) 
                        pro.Address__City__s = (String) addr.get('city');
                    if (addr.containsKey('state')) {
                        String stateInput = (String) addr.get('state');
                        pro.Address__StateCode__s = getStateCode(stateInput);
                    }
                    if (addr.containsKey('zipCode')) 
                        pro.Address__PostalCode__s = (String) addr.get('zipCode');
                    if (addr.containsKey('country')) 
                        pro.Address__CountryCode__s = (String) addr.get('country');
                }
            }
        }
        
        // Bulk UPDATE
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                HealthcarePractitionerFacility rec = toUpdate[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.recordId = rec != null ? rec.Id : null;
                resp.objectType = 'HealthcarePractitionerFacility';
                resp.recordData = rec != null ? updateIdToData.get(rec.Id) : null;
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Healthcare Professional updated successfully';
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to update Healthcare Professional: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                }
                responses.add(resp);
            }
        }
        
        // Bulk INSERT
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.objectType = 'HealthcarePractitionerFacility';
                resp.recordData = insertIndexToData.get(i);
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Healthcare Professional created successfully';
                    resp.recordId = sr.getId();
                    if (resp.recordData != null) {
                        resp.recordData.put('id', sr.getId());
                    }
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to create Healthcare Professional: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                }
                responses.add(resp);
            }
        }
        
        return responses;
    }
    
    /* ============================================================================
BULK UPDATE PERSONAL CONTACT (NULL-SAFE)
============================================================================ */
    private static List<ResponseWrapper> bulkUpdatePersonalContact(List<Map<String, Object>> records) {
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        
        // Add null check for input
        if (records == null || records.isEmpty()) {
            return responses;
        }
        
        // Collect IDs for update
        Set<String> updateIds = new Set<String>();
        for (Map<String, Object> rec : records) {
            if (rec == null) continue; 
            
            String idVal = (String) rec.get('id');
            if (!String.isBlank(idVal)) updateIds.add(idVal);
        }
        
        // Query existing Contacts
        Map<String, Contact> contactMap = new Map<String, Contact>();
        if (!updateIds.isEmpty()) {
            List<Contact> existingContacts = [
                SELECT Id, FirstName,LastName, Email, Emergency_Contact_Relationship__c,ADT_Contact__c,Authorized_Representative__c,
                MobilePhone, HomePhone, MailingStreet, MailingCity, MailingState,
                MailingPostalCode, MailingCountry, Description, Emergency_Contact__c,
                Is_PHI_Authorized__c, Is_Healthcare_Proxy__c
                FROM Contact
                WHERE Id IN :updateIds
            ];
            for (Contact c : existingContacts) {
                if (c != null && c.Id != null) { 
                    contactMap.put(c.Id, c);
                }
            }
        }
        
        List<Contact> toUpdate = new List<Contact>();
        List<Contact> toInsert = new List<Contact>();
        Map<Integer, Map<String, Object>> insertIndexToData = new Map<Integer, Map<String, Object>>();
        Map<String, Map<String, Object>> updateIdToData = new Map<String, Map<String, Object>>();
        Integer insertIndex = 0;
        
        for (Map<String, Object> bodyData : records) {
            if (bodyData == null) continue; 
            
            String idVal = (String) bodyData.get('id');
            Boolean isCreate = String.isBlank(idVal);
            Contact c;
            
            if (isCreate) {
                c = new Contact();
                c.RecordTypeId = getContactRecordTypeId();
                toInsert.add(c);
                insertIndexToData.put(insertIndex++, bodyData);
            } else {
                c = contactMap.get(idVal);
                if (c == null) {
                    ResponseWrapper resp = new ResponseWrapper();
                    resp.success = false;
                    resp.message = 'Personal Contact record not found: ' + idVal;
                    resp.errorCode = 'RECORD_NOT_FOUND';
                    resp.recordId = idVal;
                    resp.objectType = 'Contact';
                    resp.recordData = bodyData;
                    responses.add(resp);
                    continue;
                }
                toUpdate.add(c);
                updateIdToData.put(idVal, bodyData);
            }
            
            if (bodyData.containsKey('firstName') && bodyData.get('firstName') != null) 
                c.FirstName = (String) bodyData.get('firstName');
            if (isCreate && bodyData.containsKey('accountId') && bodyData.get('accountId') != null) 
                c.Account__c = (String) bodyData.get('accountId');
            if (bodyData.containsKey('lastName') && bodyData.get('lastName') != null) 
                c.LastName = (String) bodyData.get('lastName');
            if (bodyData.containsKey('email') && bodyData.get('email') != null) 
                c.Email = (String) bodyData.get('email');
            if (bodyData.containsKey('relationship') && bodyData.get('relationship') != null) 
                c.Emergency_Contact_Relationship__c = (String) bodyData.get('relationship');
            if (bodyData.containsKey('mobilePhone') && bodyData.get('mobilePhone') != null) 
                c.MobilePhone = (String) bodyData.get('mobilePhone');
            if (bodyData.containsKey('homePhone') && bodyData.get('homePhone') != null) 
                c.HomePhone = (String) bodyData.get('homePhone');
            if (bodyData.containsKey('notes') && bodyData.get('notes') != null) 
                c.Description = (String) bodyData.get('notes');
            if (bodyData.containsKey('emergencyContact') && bodyData.get('emergencyContact') != null) 
                c.Emergency_Contact__c = (Boolean) bodyData.get('emergencyContact');
            if (bodyData.containsKey('adt_contact') && bodyData.get('adt_contact') != null) 
                c.ADT_Contact__c = (Boolean) bodyData.get('adt_contact');
            if (bodyData.containsKey('authorized_representative') && bodyData.get('authorized_representative') != null) 
                c.Authorized_Representative__c = (Boolean) bodyData.get('authorized_representative');
            if (bodyData.containsKey('authorizedToDisclose') && bodyData.get('authorizedToDisclose') != null) 
                c.Is_PHI_Authorized__c = (Boolean) bodyData.get('authorizedToDisclose');
            if (bodyData.containsKey('healthcareSurrogate') && bodyData.get('healthcareSurrogate') != null) 
                c.Is_Healthcare_Proxy__c = (Boolean) bodyData.get('healthcareSurrogate');
            
            if (bodyData.containsKey('address') && bodyData.get('address') != null) {
                Map<String, Object> addressData = (Map<String, Object>) bodyData.get('address');
                if (addressData != null) {
                    if (addressData.containsKey('street') && addressData.get('street') != null) {
                        c.MailingStreet = (String) addressData.get('street');
                        
                    }
                    if (addressData.containsKey('city') && addressData.get('city') != null) {
                        c.MailingCity = (String) addressData.get('city');
                    }
                    if (addressData.containsKey('state') && addressData.get('state') != null) {
                        c.MailingState = (String) addressData.get('state');
                    } 
                    if (addressData.containsKey('zipCode') && addressData.get('zipCode') != null) {
                        c.MailingPostalCode = (String) addressData.get('zipCode');
                    }
                    if (addressData.containsKey('country') && addressData.get('country') != null) {
                        c.MailingCountry = (String) addressData.get('country');
                    }
                }
            }
        }
        
        // Bulk UPDATE
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                Contact rec = toUpdate[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.recordId = rec != null ? rec.Id : null; 
                resp.objectType = 'Contact';
                resp.recordData = rec != null ? updateIdToData.get(rec.Id) : null;
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Personal Contact updated successfully';
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to update Personal Contact: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                    system.debug('  resp.message--> update contact'+  resp.message);
                    
                }
                responses.add(resp);
            }
        }
        
        // Bulk INSERT
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.objectType = 'Contact';
                resp.recordData = insertIndexToData.get(i);
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Personal Contact created successfully';
                    resp.recordId = sr.getId();
                    // Update the data with new ID
                    if (resp.recordData != null) {
                        resp.recordData.put('id', sr.getId());
                    }
                } else {
                    resp.success = false;
                    
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to create Personal Contact: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                }
                responses.add(resp);
            }
        }
        
        return responses;
    }
    
    /* ============================================================================
BULK UPDATE PERSON ACCOUNT
============================================================================ */
    private static List<ResponseWrapper> bulkUpdatePersonAccount(List<Map<String, Object>> records) {
        Id personAccountRTId = ContactMedicalDataAPI.getPersonAccountRecordTypeId();
        List<ResponseWrapper> responses = new List<ResponseWrapper>();
        if (records == null || records.isEmpty()) {
            return responses;
        }
        Set<String> updateIds = new Set<String>();
        for (Map<String, Object> rec : records) {
            if (rec == null) continue; 
            
            String idVal = (String) rec.get('id');
            if (!String.isBlank(idVal)) updateIds.add(idVal);
        }	
        
        // Query existing Person Accounts
        Map<String, Account> accountMap = new Map<String, Account>();
        if (!updateIds.isEmpty()) {
            List<Account> existingAccounts = [
                SELECT Id, IsPersonAccount, FirstName, MiddleName, LastName,Suffix,Maiden_Name__pc,Preferred_Name__pc,
                PersonBirthdate, PersonMailingStreet, PersonMailingCity, PersonMailingState,Preferred_Language__pc,
                PersonMailingPostalCode, PersonMailingCountry, PersonOtherStreet, PersonOtherCity,
                PersonOtherState, PersonOtherPostalCode, PersonOtherCountry,Date_of_Birth__pc,Fax,
                PersonEmail, Additional_Email__pc,Salutation,sra__OptOut__c,Profile_Image_URL__c,
                PersonMobilePhone, PersonHomePhone, Work_Phone__pc,
                Occupation__pc, Marital_Status__pc, Consent_to_Call__pc, Consent_to_Text__pc,
                PersonGenderIdentity, PersonGender, Sexual_Orientation__pc, Race__pc, Ethnicity__pc,
                Living_Situation__pc, Height_in_inches__pc, Weight_in_pounds__pc,Preferred_Method_of_Contact__pc,
                Sign_Up_Date__pc, Renewal_Date__pc
                FROM Account
                WHERE Id IN :updateIds AND IsPersonAccount = true
            ];
            for (Account a : existingAccounts) {
                if (a != null && a.Id != null) { 
                    accountMap.put(a.Id, a);
                }
            }
        }
        
        List<Account> toUpdate = new List<Account>();
        List<Account> toInsert = new List<Account>();
        Map<Integer, Map<String, Object>> insertIndexToData = new Map<Integer, Map<String, Object>>();
        Map<String, Map<String, Object>> updateIdToData = new Map<String, Map<String, Object>>();
        Integer insertIndex = 0;
        
        for (Map<String, Object> bodyData : records) {
            if (bodyData == null) continue; 
            
            String idVal = (String) bodyData.get('id');
            Boolean isCreate = String.isBlank(idVal);
            Account a;
            
            if (isCreate) {
                a = new Account(RecordTypeId = personAccountRtId); 
                toInsert.add(a);
                insertIndexToData.put(insertIndex++, bodyData);
            } else {
                a = accountMap.get(idVal);
                if (a == null) {
                    ResponseWrapper resp = new ResponseWrapper();
                    resp.success = false;
                    resp.message = 'Person Account record not found: ' + idVal;
                    resp.errorCode = 'RECORD_NOT_FOUND';
                    resp.recordId = idVal;
                    resp.objectType = 'Account';
                    resp.recordData = bodyData;
                    responses.add(resp);
                    continue;
                }
                toUpdate.add(a);
                updateIdToData.put(idVal, bodyData);
            }
            
            // Now a is guaranteed to be non-null - Map simple fields
            if (bodyData.containsKey('firstName') && bodyData.get('firstName') != null) 
                a.FirstName = (String) bodyData.get('firstName');
            if (bodyData.containsKey('salutation') && bodyData.get('salutation') != null) 
                a.Salutation = (String) bodyData.get('salutation');
            if (bodyData.containsKey('lastName') && bodyData.get('lastName') != null) 
                a.LastName = (String) bodyData.get('lastName');
            if (bodyData.containsKey('preferredName') && bodyData.get('preferredName') != null) 
                a.Preferred_Name__pc = (String) bodyData.get('preferredName'); 
            if (bodyData.containsKey('preferredLanguage') && bodyData.get('preferredLanguage') != null) 
                a.Preferred_Language__pc = (String) bodyData.get('preferredLanguage');  
            if (bodyData.containsKey('maidenname') && bodyData.get('maidenname') != null) 
                a.Maiden_Name__pc = (String) bodyData.get('maidenname');
            if (bodyData.containsKey('suffix') && bodyData.get('suffix') != null) 
                a.Suffix = (String) bodyData.get('suffix');
            if (bodyData.containsKey('email') && bodyData.get('email') != null) 
                a.PersonEmail = (String) bodyData.get('email');
            if (bodyData.containsKey('additionalEmail') && bodyData.get('additionalEmail') != null) 
                a.Additional_Email__pc = (String) bodyData.get('additionalEmail');
            if (bodyData.containsKey('status') && bodyData.get('status') != null) 
                a.Status__c = (String) bodyData.get('status');
            if (bodyData.containsKey('mobilePhone') && bodyData.get('mobilePhone') != null) 
                a.PersonMobilePhone = (String) bodyData.get('mobilePhone');
            if (bodyData.containsKey('accountFax') && bodyData.get('accountFax') != null) 
                a.Fax = (String) bodyData.get('accountFax');
            if (bodyData.containsKey('homePhone') && bodyData.get('homePhone') != null) 
                a.PersonHomePhone = (String) bodyData.get('homePhone');
            if (bodyData.containsKey('workPhone') && bodyData.get('workPhone') != null) 
                a.Work_Phone__pc = (String) bodyData.get('workPhone');
            if (bodyData.containsKey('preferredContactMethod') && bodyData.get('preferredContactMethod') != null) 
                a.Preferred_Method_of_Contact__pc = (String) bodyData.get('preferredContactMethod');
            if (bodyData.containsKey('occupation') && bodyData.get('occupation') != null) 
                a.Occupation__pc = (String) bodyData.get('occupation');
            if (bodyData.containsKey('maritalStatus') && bodyData.get('maritalStatus') != null) 
                a.Marital_Status__pc = (String) bodyData.get('maritalStatus');
            if (bodyData.containsKey('genderIdentity') && bodyData.get('genderIdentity') != null) 
                a.PersonGenderIdentity = (String) bodyData.get('genderIdentity');
            if (bodyData.containsKey('biologicalSexAtBirth') && bodyData.get('biologicalSexAtBirth') != null) 
                a.Biological_Sex_at_Birth__c = (String) bodyData.get('biologicalSexAtBirth');
            if (bodyData.containsKey('sexualOrientation') && bodyData.get('sexualOrientation') != null) 
                a.Sexual_Orientation__pc = (String) bodyData.get('sexualOrientation');
            if (bodyData.containsKey('race') && bodyData.get('race') != null) 
                a.Race__pc = (String) bodyData.get('race');
            if (bodyData.containsKey('ethnicity') && bodyData.get('ethnicity') != null) 
                a.Ethnicity__pc = (String) bodyData.get('ethnicity');
            if (bodyData.containsKey('livingSituation') && bodyData.get('livingSituation') != null) 
                a.Living_Situation__pc = (String) bodyData.get('livingSituation');
            if (bodyData.containsKey('dateOfBirth') && bodyData.get('dateOfBirth') != null) 
                a.Date_of_Birth__pc = parseDate(bodyData.get('dateOfBirth'));
            Object consentVal = bodyData.get('communicationConsent');
            Boolean consentBool = false; 
            if (consentVal != null) {
                if (consentVal instanceof Boolean) {
                    consentBool = (Boolean) consentVal;
                } else if (consentVal instanceof String) {
                    consentBool = ((String) consentVal).trim().toLowerCase() == 'true';
                }
            }

            a.sra__OptOut__c      = consentBool;
            a.Consent_to_Call__pc = consentBool;
            a.Consent_to_Text__pc = consentBool; 

            a.Height_in_inches__pc = parseDecimal(bodyData.get('height'), a.Height_in_inches__pc);
            a.Weight_in_pounds__pc = parseDecimal(bodyData.get('weight'), a.Weight_in_pounds__pc);
            
            if (bodyData.containsKey('dateOfBirth') && bodyData.get('dateOfBirth') != null) 
                a.PersonBirthdate = parseDate(bodyData.get('dateOfBirth'));
            if (bodyData.containsKey('signUpDate') && bodyData.get('signUpDate') != null) 
                a.Sign_Up_Date__pc = parseDate(bodyData.get('signUpDate'));
            if (bodyData.containsKey('renewalDate') && bodyData.get('renewalDate') != null) 
                a.Renewal_Date__pc = parseDate(bodyData.get('renewalDate'));
            if (bodyData.containsKey('profile_picture') && bodyData.get('profile_picture') != null) 
                a.Profile_Image_URL__c = (String) bodyData.get('profile_picture');
            Object mailingAddr = bodyData.get('mailingAddress');
            if (mailingAddr != null) {
                mapAddress((Map<String,Object>)mailingAddr, 'PersonMailing', a);
            }
            
            Object otherAddr = bodyData.get('otherAddress');
            if (otherAddr != null) {
                mapAddress((Map<String,Object>)otherAddr, 'PersonOther', a);
            }
        }
        
        // Bulk UPDATE
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                Account rec = toUpdate[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.recordId = rec != null ? rec.Id : null; 
                resp.objectType = 'Account';
                resp.recordData = rec != null ? updateIdToData.get(rec.Id) : null;
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Person Account updated successfully';
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to update Person Account: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                    system.debug('  resp.message--> update account'+  resp.message);
                }
                responses.add(resp);
            }
        }
        
        // Bulk INSERT
        if (!toInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(toInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                
                ResponseWrapper resp = new ResponseWrapper();
                resp.objectType = 'Account';
                resp.recordData = insertIndexToData.get(i);
                
                if (sr != null && sr.isSuccess()) {
                    resp.success = true;
                    resp.message = 'Person Account created successfully';
                    resp.recordId = sr.getId();
                    if (resp.recordData != null) {
                        resp.recordData.put('id', sr.getId());
                    }
                } else {
                    resp.success = false;
                    String errorMsg = (sr != null && sr.getErrors() != null && sr.getErrors().size() > 0) 
                        ? sr.getErrors()[0].getMessage() 
                        : 'Unknown error';
                    resp.message = 'Failed to create Person Account: ' + errorMsg;
                    resp.errorCode = 'DML_ERROR';
                    resp.errorDetails = errorMsg;
                    system.debug('  resp.message--> create account'+  resp.message);
                }
                responses.add(resp);
            }
        }
        
        return responses;
    } 
// file
public static List<ResponseWrapper> bulkUpsertFiles(List<Map<String, Object>> records) {
    List<ResponseWrapper> responses = new List<ResponseWrapper>();
    if (records == null || records.isEmpty()) return responses;
    List<Map<String, Object>> results = FileUpsertHelper.processFiles(records);

    for (Map<String, Object> result : results) {
        ResponseWrapper resp = new ResponseWrapper();
        resp.objectType = 'ContentVersion';
        resp.recordData = result;
        resp.success    = (Boolean) result.get('success');
        resp.message    = (String)  result.get('message');
        resp.recordId   = (String)  result.get('id');
        responses.add(resp);
    }

    return responses;
}
    
    
    // Helper methods
    private static void mapAddress(Map<String, Object> addr, String prefix, Account a) {
        if (addr == null) return;
        if (addr.containsKey('street')) a.put(prefix+'Street', addr.get('street'));
        if (addr.containsKey('city')) a.put(prefix+'City', addr.get('city'));
        if (addr.containsKey('state')) a.put(prefix+'State', addr.get('state'));
        if (addr.containsKey('zipCode')) a.put(prefix+'PostalCode', addr.get('zipCode'));
        if (addr.containsKey('country')) a.put(prefix+'Country', addr.get('country'));
    }
    
    @TestVisible
    private static Decimal parseDecimal(Object val, Decimal defaultVal) {
        if (val == null) return defaultVal;
        
        if (val instanceof Decimal) {
            return (Decimal) val;
        }
        
        if (val instanceof String) {
            String strVal = ((String) val).trim();
            if (String.isNotBlank(strVal)) {
                try {
                    return Decimal.valueOf(strVal);
                } catch (Exception e) {
                    return defaultVal;
                }
            }
        }
        
        return defaultVal;
    }
    
    /*============================================================================
UTILITY METHODS - DATE/DATETIME PARSING
============================================================================ */
    private static Date parseDate(Object dateValue) {
        if (dateValue == null) return null;
        
        try {
            if (dateValue instanceof String) {
                String dateStr = (String) dateValue;
                if (String.isBlank(dateStr)) return null;
                return Date.valueOf(dateStr);
            }
        } catch (Exception e) {
            System.debug('Error parsing date: ' + e.getMessage());
        }
        return null;
    }
    private static Datetime parseDatetime(Object datetimeValue) {
        if (datetimeValue == null) return null;
        
        try {
            if (datetimeValue instanceof String) {
                String datetimeStr = (String) datetimeValue;
                if (String.isBlank(datetimeStr)) return null;
                return Datetime.valueOf(datetimeStr);
            }
        } catch (Exception e) {
            System.debug('Error parsing datetime: ' + e.getMessage());
        }
        return null;
    }
    
    /* ============================================================================
RESPONSE WRAPPERS
============================================================================ */
    global class BatchResponseWrapper {
        public Boolean success;
        public String message;
        public String errorCode;
        public String errorDetails;
        public String errorStackTrace;
        public Integer totalRecords;
        public Integer successCount;
        public Integer failureCount;
        public Map<String, List<Map<String, Object>>> data;
        
        public BatchResponseWrapper() {
            this.totalRecords = 0;
            this.successCount = 0;
            this.failureCount = 0;
            this.data = new Map<String, List<Map<String, Object>>>();
        }
    }
    global class ResponseWrapper {
        public Boolean success;
        public String message;
        public String errorCode;
        public String errorDetails;
        public String errorStackTrace;
        public String recordId;
        public String objectType;
        public Map<String, Object> recordData;
    }
    
}