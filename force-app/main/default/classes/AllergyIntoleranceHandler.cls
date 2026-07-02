public without sharing class AllergyIntoleranceHandler {
    
    public static void parseAndInsertAllergies(String rawJson) {
        if (String.isBlank(rawJson)) return;
        
        try {
            Object parsed = JSON.deserializeUntyped(rawJson);
            if (!(parsed instanceof Map<String, Object>)) return;
            
            Map<String, Object> resource = (Map<String, Object>) parsed;
            String resourceType = (String) resource.get('resourceType');
            
            List<Map<String, Object>> allergyResources = new List<Map<String, Object>>();
            
            if ('Bundle'.equals(resourceType)) {
                List<Object> entries = (List<Object>) resource.get('entry');
                if (entries != null) {
                    for (Object e : entries) {
                        if (!(e instanceof Map<String, Object>)) continue;
                        Map<String, Object> entry = (Map<String, Object>) e;
                        Map<String, Object> res = (Map<String, Object>) entry.get('resource');
                        if (res == null) continue;
                        if ('AllergyIntolerance'.equals((String) res.get('resourceType'))) {
                            allergyResources.add(res);
                        }
                    }
                }
            } else if ('AllergyIntolerance'.equals(resourceType)) {
                allergyResources.add(resource);
            }
            
            if (allergyResources.isEmpty()) return;
            
            Set<String> incomingAllergyIds = new Set<String>();
            for (Map<String, Object> res : allergyResources) {
                if (res.containsKey('id') && res.get('id') != null) {
                    incomingAllergyIds.add((String) res.get('id'));
                }
            }
            
            Set<String> existingAllergyIds = new Set<String>();
            if (!incomingAllergyIds.isEmpty()) {
                for (AllergyIntolerance a : [
                    SELECT AllergyId__c
                    FROM AllergyIntolerance
                    WHERE AllergyId__c IN :incomingAllergyIds
                ]) {
                    existingAllergyIds.add(a.AllergyId__c);
                }
            }
            
            Set<String> deletedAllergyIds = new Set<String>();
            if (!incomingAllergyIds.isEmpty()) {
                for (Deleted_Record_Audit__c audit : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE External_Id_Metriport__c IN :incomingAllergyIds
                    AND Object_API_Name__c = 'AllergyIntolerance'
                ]) {
                    deletedAllergyIds.add(audit.External_Id_Metriport__c);
                }
            }

            /* -------------------------
               Dedup key: Allergy_Name__c + Generic__c
               Fetch existing composite keys from AllergyIntolerance
            -------------------------- */
            // Collect patient SF IDs from incoming resources to scope dedupe query
            Set<String> allergyPatientFhirIds = new Set<String>();
            for (Map<String, Object> res2 : allergyResources) {
                Map<String, Object> pm = (Map<String, Object>) res2.get('patient');
                if (pm != null) {
                    String ref2 = (String) pm.get('reference');
                    if (!String.isBlank(ref2) && ref2.contains('/')) allergyPatientFhirIds.add(ref2.split('/')[1]);
                }
            }
            Set<Id> allergyPatientIds = new Set<Id>();
            if (!allergyPatientFhirIds.isEmpty()) {
                for (Account a : [SELECT Id FROM Account WHERE IsPersonAccount = true AND Metriport_Patient_Id__c IN :allergyPatientFhirIds]) {
                    allergyPatientIds.add(a.Id);
                }
            }
            Set<String> existingAllergyDedupeKeys = new Set<String>();
            if (!allergyPatientIds.isEmpty()) {
                for (AllergyIntolerance a : [
                    SELECT Allergy_Name__c, Generic__c
                    FROM AllergyIntolerance
                    WHERE Allergy_Name__c != null
                      AND PatientId IN :allergyPatientIds
                ]) {
                    String key = buildAllergyDedupeKey(a.Allergy_Name__c, a.Generic__c);
                    if (!String.isBlank(key)) existingAllergyDedupeKeys.add(key);
                }
            }
            
            List<AllergyIntolerance> allergiesToInsert = new List<AllergyIntolerance>();
            Set<String> inFlightAllergyDedupeKeys = new Set<String>();

            for (Map<String, Object> res : allergyResources) {
                String allergyId = (String) res.get('id');

                if (existingAllergyIds.contains(allergyId)) continue;
                
                if (deletedAllergyIds.contains(allergyId)) {
                    System.debug('⏭️ Skipping deleted AllergyIntolerance: ' + allergyId);
                    continue;
                }
                
                AllergyIntolerance allergy = parseSingleAllergy(res);
                if (allergy == null) continue;

                if (String.isBlank(allergy.Allergy_Name__c)) {
                    System.debug('⏭️ Skipping AllergyIntolerance (no Allergy Name): ' + allergyId);
                    continue;
                }

                if (allergy.Allergy_Name__c.trim().equalsIgnoreCase('No Data Available')) {
                    System.debug('⏭️ Skipping AllergyIntolerance (No Data Available name): ' + allergyId);
                    continue;
                }

                allergy.AllergyId__c = allergyId;

                // Dedup by composite key: Allergy_Name__c + Generic__c
                String dedupeKey = buildAllergyDedupeKey(allergy.Allergy_Name__c, allergy.Generic__c);
                if (!String.isBlank(dedupeKey)) {
                    if (existingAllergyDedupeKeys.contains(dedupeKey) || inFlightAllergyDedupeKeys.contains(dedupeKey)) {
                        System.debug('⏭️ Skipping AllergyIntolerance (Composite Duplicate): ' + dedupeKey);
                        continue;
                    }
                    inFlightAllergyDedupeKeys.add(dedupeKey);
                }

                allergiesToInsert.add(allergy);
            }
            
            if (!allergiesToInsert.isEmpty()) {
                Database.SaveResult[] results = Database.insert(allergiesToInsert, false);
                
                List<Error_Log__c> errorLogs = new List<Error_Log__c>();
                Integer successCount = 0;
                
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successCount++;
                    } else {
                        List<String> errorMessages = new List<String>();
                        for (Database.Error err : results[i].getErrors()) {
                            errorMessages.add(
                                'Status: ' + err.getStatusCode() +
                                ' | Message: ' + err.getMessage() +
                                ' | Fields: ' + String.join(err.getFields(), ', ')
                            );
                        }
                        AllergyIntolerance failedAllergy = allergiesToInsert[i];
                        errorLogs.add(new Error_Log__c(
                            Object_API_Name__c    = 'AllergyIntolerance',
                            Error_Message__c      = String.join(errorMessages, '\n'),
                            Record_External_Id__c = failedAllergy.AllergyId__c,
                            Context__c            = 'parseAndInsertAllergies',
                            Stack_Trace__c        = 'PatientId: ' + failedAllergy.PatientId +
                                                    ' | AllergyId: ' + failedAllergy.AllergyId__c
                        ));
                    }
                }
                
                if (!errorLogs.isEmpty()) {
                    Database.insert(errorLogs, false);
                    System.debug('⚠️ Failed AllergyIntolerance inserts logged: ' + errorLogs.size());
                }
                System.debug('✅ Inserted AllergyIntolerance records: ' + successCount +
                             ' | Failed: ' + (allergiesToInsert.size() - successCount));
            }
            
        } catch (Exception ex) {
            System.debug('❌ AllergyIntoleranceHandler error: ' + ex.getMessage());
        }
    }

    private static String buildAllergyDedupeKey(String allergyName, String generic) {
        String namePart    = String.isBlank(allergyName) ? '' : allergyName.trim().toLowerCase();
        String genericPart = String.isBlank(generic)     ? '' : generic.trim().toLowerCase();
        if (String.isBlank(namePart) && String.isBlank(genericPart)) return null;
        return namePart + '|' + genericPart;
    }
    
    private static AllergyIntolerance parseSingleAllergy(Map<String, Object> resource) {
        if (resource == null) return null;
        
        AllergyIntolerance allergy = new AllergyIntolerance();
        allergy.PatientId = resolvePatientContact(resource);
        
        DateTime onsetDateTime = parseOnsetDateTime(resource);
        if (onsetDateTime != null) {
            allergy.OnsetStartDateTime = onsetDateTime;
        }
        
        parseReaction(resource, allergy);
        
        allergy.VerificationStatus = parseCodeableConcept((Map<String, Object>) resource.get('verificationStatus'));
        allergy.Status = parseCodeableConcept((Map<String, Object>) resource.get('clinicalStatus'));
        
        return allergy;
    }
    
    private static Id resolvePatientContact(Map<String, Object> resource) {
        Map<String, Object> patientMap = (Map<String, Object>) resource.get('patient');
        if (patientMap == null) return null;
        
        String reference = (String) patientMap.get('reference');
        if (String.isBlank(reference)) return null;
        
        String fhirId = reference.contains('/') ? reference.split('/')[1] : reference;
        if (String.isBlank(fhirId)) return null;
        
        List<Account> accs = [
            SELECT PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            AND Metriport_Patient_Id__c = :fhirId
            LIMIT 1
        ];
        
        return accs.isEmpty() ? null : accs[0].Id;
    }
    
    private static String parseCodeableConcept(Map<String, Object> codeableConcept) {
        if (codeableConcept == null) return null;
        
        List<Object> codingList = (List<Object>) codeableConcept.get('coding');
        if (codingList != null && !codingList.isEmpty()) {
            Object firstCoding = codingList[0];
            if (firstCoding instanceof Map<String, Object>) {
                String display = (String) ((Map<String, Object>) firstCoding).get('display');
                if (!String.isBlank(display)) return display;
                String code = (String) ((Map<String, Object>) firstCoding).get('code');
                return code;
            }
        }
        
        return (String) codeableConcept.get('text');
    }
    
    private static DateTime parseOnsetDateTime(Map<String, Object> resource) {
        Object onsetObj = resource.get('onsetDateTime');
        if (onsetObj instanceof String) {
            try {
                return DateTime.valueOfGmt((String) onsetObj);
            } catch (Exception e) {
                return null;
            }
        }
        
        Map<String, Object> onsetPeriod = (Map<String, Object>) resource.get('onsetPeriod');
        if (onsetPeriod != null) {
            String start = (String) onsetPeriod.get('start');
            if (!String.isBlank(start)) {
                try {
                    return DateTime.valueOfGmt(start);
                } catch (Exception e) {
                    return null;
                }
            }
        }
        
        return null;
    }
    
    private static void parseReaction(Map<String, Object> resource, AllergyIntolerance allergy) {
        List<Object> reactions = (List<Object>) resource.get('reaction');
        if (reactions == null || reactions.isEmpty()) return;
        
        Map<String, Object> reaction = (Map<String, Object>) reactions[0];
        String severity = (String) reaction.get('severity');
        if (!String.isBlank(severity)) allergy.Severity = severity;
        
        Map<String, Object> substance = (Map<String, Object>) reaction.get('substance');
        if (substance == null) return;
        
        String allergyName = (String) substance.get('text');
        allergy.Allergy_Name__c = allergyName;
        
        List<Object> codingList = (List<Object>) substance.get('coding');
        if (codingList != null) {
            Set<String> displays = new Set<String>();
            for (Object cObj : codingList) {
                if (cObj instanceof Map<String, Object>) {
                    String display = (String) ((Map<String, Object>) cObj).get('display');
                    if (!String.isBlank(display)) displays.add(display);
                }
            }
            if (!displays.isEmpty()) {
                String genericName = String.join(new List<String>(displays), ', ');
                allergy.Generic__c = genericName;
                allergy.Combine_allergy_and_Generic__c = allergyName + ',' + genericName;
            }else{
                allergy.Combine_allergy_and_Generic__c = allergyName;
            }
        }
    }
}