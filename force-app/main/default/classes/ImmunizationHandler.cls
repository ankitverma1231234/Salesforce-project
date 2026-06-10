public without sharing class ImmunizationHandler {
    
    public static void parseAndInsertImmunizations(String rawJson) {
        if (String.isBlank(rawJson)) return;
        
        try {
            Object parsed = JSON.deserializeUntyped(rawJson);
            if (!(parsed instanceof Map<String, Object>)) return;
            
            Map<String, Object> json = (Map<String, Object>) parsed;
            
            List<Map<String, Object>> immunizationResources = new List<Map<String, Object>>();
            Set<String> incomingImmunizationIds = new Set<String>();
            
            if ('Bundle'.equals(json.get('resourceType'))) {
                List<Object> entries = (List<Object>) json.get('entry');
                if (entries != null) {
                    for (Object e : entries) {
                        Map<String, Object> res =
                            (Map<String, Object>) ((Map<String, Object>) e).get('resource');
                        if (res != null && 'Immunization'.equals(res.get('resourceType'))) {
                            immunizationResources.add(res);
                            if (res.get('id') != null) {
                                incomingImmunizationIds.add((String) res.get('id'));
                            }
                        }
                    }
                }
            } else if ('Immunization'.equals(json.get('resourceType'))) {
                immunizationResources.add(json);
                if (json.get('id') != null) {
                    incomingImmunizationIds.add((String) json.get('id'));
                }
            }
            
            if (immunizationResources.isEmpty()) return;
            
            Set<String> existingIds = new Set<String>();
            if (!incomingImmunizationIds.isEmpty()) {
                for (PatientImmunization pi : [
                    SELECT ImmunizationId__c
                    FROM PatientImmunization
                    WHERE ImmunizationId__c IN :incomingImmunizationIds
                ]) {
                    existingIds.add(pi.ImmunizationId__c);
                }
            }
            
            Set<String> deletedImmunizationIds = new Set<String>();
            if (!incomingImmunizationIds.isEmpty()) {
                for (Deleted_Record_Audit__c audit : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE External_Id_Metriport__c IN :incomingImmunizationIds
                    AND Object_API_Name__c = 'PatientImmunization'
                ]) {
                    deletedImmunizationIds.add(audit.External_Id_Metriport__c);
                }
            }

            /* -------------------------
               Dedup key: Vaccine_Name__c + VaccinationDate + Dose__c
               Fetch existing composite keys from PatientImmunization
            -------------------------- */
            // Collect patient SF IDs from incoming resources to scope dedupe query
            Set<String> immPatientFhirIds = new Set<String>();
            for (Map<String, Object> res2 : immunizationResources) {
                Map<String, Object> pm = (Map<String, Object>) res2.get('patient');
                if (pm != null) {
                    String ref2 = (String) pm.get('reference');
                    if (!String.isBlank(ref2) && ref2.contains('/')) immPatientFhirIds.add(ref2.split('/')[1]);
                }
            }
            Set<Id> immPatientIds = new Set<Id>();
            if (!immPatientFhirIds.isEmpty()) {
                for (Account a : [SELECT Id FROM Account WHERE Metriport_Patient_Id__c IN :immPatientFhirIds]) {
                    immPatientIds.add(a.Id);
                }
            }
            Set<String> existingImmDedupeKeys = new Set<String>();
            if (!immPatientIds.isEmpty()) {
                for (PatientImmunization pi : [
                    SELECT Vaccine_Name__c, VaccinationDate, Dose__c
                    FROM PatientImmunization
                    WHERE Vaccine_Name__c != null
                      AND PatientId IN :immPatientIds
                ]) {
                    String key = buildImmunizationDedupeKey(pi.Vaccine_Name__c, pi.VaccinationDate, pi.Dose__c);
                    if (!String.isBlank(key)) existingImmDedupeKeys.add(key);
                }
            }
            
            List<PatientImmunization> toInsert = new List<PatientImmunization>();
            Set<String> inFlightImmDedupeKeys = new Set<String>();
            
            for (Map<String, Object> res : immunizationResources) {
                String immId = (String) res.get('id');
                
                if (existingIds.contains(immId)) continue;
                if (deletedImmunizationIds.contains(immId)) {
                    System.debug('⏭️ Skipping deleted Immunization: ' + immId);
                    continue;
                }
                
                PatientImmunization imm = parseSingleImmunization(res);
                if (imm == null) continue;

                // Dedup by composite key: Vaccine_Name__c + VaccinationDate + Dose__c
                String dedupeKey = buildImmunizationDedupeKey(imm.Vaccine_Name__c, imm.VaccinationDate, imm.Dose__c);
                if (!String.isBlank(dedupeKey)) {
                    if (existingImmDedupeKeys.contains(dedupeKey) || inFlightImmDedupeKeys.contains(dedupeKey)) {
                        System.debug('⏭️ Skipping Immunization (Composite Duplicate): ' + dedupeKey);
                        continue;
                    }
                    inFlightImmDedupeKeys.add(dedupeKey);
                }

                toInsert.add(imm);
            }
            
            if (!toInsert.isEmpty()) {
                Database.SaveResult[] results = Database.insert(toInsert, false);
                
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
                        PatientImmunization failedImm = toInsert[i];
                        errorLogs.add(new Error_Log__c(
                            Object_API_Name__c    = 'PatientImmunization',
                            Error_Message__c      = String.join(errorMessages, '\n'),
                            Record_External_Id__c = failedImm.ImmunizationId__c,
                            Context__c            = 'parseAndInsertImmunizations',
                            Stack_Trace__c        = 'PatientId: ' + failedImm.PatientId +
                                                    ' | ImmunizationId: ' + failedImm.ImmunizationId__c
                        ));
                    }
                }
                
                if (!errorLogs.isEmpty()) {
                    Database.insert(errorLogs, false);
                    System.debug('⚠️ Failed PatientImmunization inserts logged: ' + errorLogs.size());
                }
                System.debug('✅ Inserted PatientImmunization records: ' + successCount +
                             ' | Failed: ' + (toInsert.size() - successCount));
            }
            
        } catch (Exception e) {
            System.debug('❌ ImmunizationHandler error: ' + e.getMessage());
        }
    }

    private static String buildImmunizationDedupeKey(String vaccineName, Datetime vaccinationDate, String dose) {
        String namePart = String.isBlank(vaccineName) ? '' : vaccineName.trim().toLowerCase();
        String datePart = (vaccinationDate != null)   ? String.valueOf(vaccinationDate) : '';
        String dosePart = String.isBlank(dose)        ? '' : dose.trim().toLowerCase();
        if (String.isBlank(namePart) && String.isBlank(datePart) && String.isBlank(dosePart)) return null;
        return namePart + '|' + datePart + '|' + dosePart;
    }
    
    private static PatientImmunization parseSingleImmunization(Map<String, Object> resource) {
        PatientImmunization imm = new PatientImmunization();
        
        imm.ImmunizationId__c = (String) resource.get('id');
        imm.PatientId         = resolvePatient(resource);
        imm.Status            = (String) resource.get('status');
        imm.VaccineCodeId     = getVaccineCodeId();

        Map<String, Object> vaccineCode = (Map<String, Object>) resource.get('vaccineCode');
        if (vaccineCode != null) {
            imm.Vaccine_Name__c = (String) vaccineCode.get('text');
        }
        
        parseOccurrence(resource, imm);
        
        Map<String, Object> doseQty = (Map<String, Object>) resource.get('doseQuantity');
        if (doseQty != null) {
            Object val  = doseQty.get('value');
            String unit = (String) doseQty.get('unit');
            if (val != null) {
                imm.Dose__c = String.valueOf(val) + (String.isBlank(unit) ? '' : ' ' + unit);
            }
        }
        
        Map<String, Object> manufacturer = (Map<String, Object>) resource.get('manufacturer');
        if (manufacturer != null) {
            imm.Manufacturer__c = (String) manufacturer.get('display');
        }
        
        String practitionerFhirId;
        List<Object> performers = (List<Object>) resource.get('performer');
        if (performers != null && !performers.isEmpty()) {
            Map<String, Object> perf  = (Map<String, Object>) performers[0];
            Map<String, Object> actor = (Map<String, Object>) perf.get('actor');
            if (actor != null) {
                String ref = (String) actor.get('reference');
                if (!String.isBlank(ref) && ref.startsWith('Practitioner/')) {
                    practitionerFhirId = ref.substring(13);
                }
            }
        }
        imm.Performer__c = resolvePractitioner(practitionerFhirId);
        
        return imm;
    }
    
    private static Id resolvePatient(Map<String, Object> resource) {
        Map<String, Object> patient = (Map<String, Object>) resource.get('patient');
        if (patient == null) return null;
        
        String ref = (String) patient.get('reference');
        if (String.isBlank(ref)) return null;
        
        String fhirId = ref.contains('/') ? ref.split('/')[1] : ref;
        
        List<Account> accs = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = :fhirId
            LIMIT 1
        ];
        return accs.isEmpty() ? null : accs[0].Id;
    }
    
    private static Id resolvePractitioner(String practitionerFhirId) {
        if (String.isBlank(practitionerFhirId)) return null;
        List<HealthcarePractitionerFacility> hp = [
            SELECT Id
            FROM HealthcarePractitionerFacility
            WHERE PractitionerId__c = :practitionerFhirId
            LIMIT 1
        ];
        return hp.isEmpty() ? null : hp[0].Id;
    }
    
    private static Id cachedVaccineCodeId;
    
    private static Id getVaccineCodeId() {
        if (cachedVaccineCodeId != null) return cachedVaccineCodeId;
        List<CodeSetBundle> codes = [
            SELECT Id
            FROM CodeSetBundle
            WHERE Name = 'Test Vaccine'
            LIMIT 1
        ];
        cachedVaccineCodeId = codes.isEmpty() ? null : codes[0].Id;
        return cachedVaccineCodeId;
    }
    
    private static void parseOccurrence(Map<String, Object> resource, PatientImmunization imm) {
        Object occ = resource.get('occurrenceDateTime');
        if (!(occ instanceof String)) return;
        
        try {
            String dt = ((String) occ).replace('T', ' ').replace('Z', '');
            if (dt.contains('.')) dt = dt.substring(0, dt.indexOf('.'));
            imm.VaccinationDate = Datetime.valueOfGmt(dt);
        } catch (Exception e) {
            System.debug('⚠️ Date parse failed: ' + occ);
        }
    }
}