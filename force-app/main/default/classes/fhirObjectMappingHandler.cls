public without sharing class fhirObjectMappingHandler {

public static void parseAndInsertMedications(String rawJson) {
    if (String.isBlank(rawJson)) return;

    try {
        Map<String, Object> jsonData = (Map<String, Object>) JSON.deserializeUntyped(rawJson);

        List<Map<String, Object>> medResources = new List<Map<String, Object>>();
        Set<String> patientIds = new Set<String>();

        if ('Bundle'.equals(jsonData.get('resourceType'))) {
            List<Object> entries = (List<Object>) jsonData.get('entry');
            if (entries != null) {
                for (Object o : entries) {
                    Map<String, Object> res = (Map<String, Object>) ((Map<String, Object>) o).get('resource');
                    if (res == null) continue;

                    if ('Medication'.equals(res.get('resourceType'))) {
                        medResources.add(res);
                    }

                    if ('Patient'.equals(res.get('resourceType'))) {
                        String pid = (String) res.get('id');
                        if (!String.isBlank(pid)) patientIds.add(pid);
                    }
                }
            }
        } else if ('Medication'.equals(jsonData.get('resourceType'))) {
            medResources.add(jsonData);
        }

        if (medResources.isEmpty() || patientIds.isEmpty()) return;

        Map<String, Id> patientMap = new Map<String, Id>();
        for (Account p : [
            SELECT Id, Metriport_patient_id__c
            FROM Account
            WHERE Metriport_patient_id__c IN :patientIds
        ]) {
            patientMap.put(p.Metriport_patient_id__c, p.Id);
        }

        if (patientMap.isEmpty()) return;

        String bundlePatientId = patientIds.iterator().next();
        Id patientSfId = patientMap.get(bundlePatientId);
        if (patientSfId == null) return;

        Set<String> medIds = new Set<String>();
        for (Map<String, Object> res : medResources) {
            String medId = (String) res.get('id');
            if (!String.isBlank(medId)) medIds.add(medId);
        }

        Map<String, Medication> existingMeds = new Map<String, Medication>();
        for (Medication m : [
            SELECT Id, MedicationId__c
            FROM Medication
            WHERE MedicationId__c IN :medIds
        ]) {
            existingMeds.put(m.MedicationId__c, m);
        }
        
        Set<String> deletedMedIds = new Set<String>();

            for (Deleted_Record_Audit__c del : [
                SELECT External_Id_Metriport__c
                FROM Deleted_Record_Audit__c
                WHERE External_Id_Metriport__c IN :medIds
                AND Object_API_Name__c = 'Medication'
            ]) {
                deletedMedIds.add(del.External_Id_Metriport__c);
            }

        List<Medication> medsToInsert = new List<Medication>();

        for (Map<String, Object> res : medResources) {
            String medId = (String) res.get('id');
            if (existingMeds.containsKey(medId)) continue;
            if (deletedMedIds.contains(medId)) continue;

            Medication med = parseSingleMedication(res);

            if ('completed'.equalsIgnoreCase(med.Status)) {
                System.debug('⏭️ Skipping Medication (status = completed): ' + medId);
                continue;
            }

            med.Patient__c = patientSfId;

 Map<String, Object> amountMap = (Map<String, Object>) res.get('amount');

    if (amountMap != null) {
        Map<String, Object> numerator =
            (Map<String, Object>) amountMap.get('numerator');
    
        if (numerator != null) {
    
            Decimal valueDec;
            String unitStr;
    
            if (numerator.get('value') != null) {
                valueDec = (Decimal) numerator.get('value');
            }
    
            if (numerator.get('unit') != null) {
                unitStr = String.valueOf(numerator.get('unit'));
            }
    
            if (valueDec != null && unitStr != null) {
                med.Amount__c = String.valueOf(valueDec) + ' ' + unitStr;
                System.debug('✅ Amount Mapped: ' + med.Amount__c);
            }
        }
    }

            medsToInsert.add(med);
        }

        if (!medsToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(medsToInsert, false);

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

                    Medication failedMed = medsToInsert[i];

                    errorLogs.add(new Error_Log__c(
                        Object_API_Name__c    = 'Medication',
                        Error_Message__c      = String.join(errorMessages, '\n'),
                        Record_External_Id__c = failedMed.MedicationId__c,
                        Context__c            = 'parseAndInsertMedications',
                        Stack_Trace__c        = 'Patient__c: ' + failedMed.Patient__c +
                                                ' | MedicationId: ' + failedMed.MedicationId__c
                    ));
                }
            }

            if (!errorLogs.isEmpty()) {
                Database.insert(errorLogs, false);
                System.debug('⚠️ Failed Medication inserts logged: ' + errorLogs.size());
            }

            System.debug('✅ Inserted ' + successCount + ' Medication record(s) | Failed: ' + (medsToInsert.size() - successCount));
        }

    } catch (Exception e) {
        System.debug('❌ Error parsing Medication: ' + e.getMessage());
    }
}

/* -------------------------
   Helper: meta.lastUpdated 12-month gate
   Returns true if lastUpdated is within the last 12 months (or missing).
-------------------------- */
private static Boolean isWithin12Months(Map<String, Object> resource) {
    Object metaRaw = resource.get('meta');
    if (!(metaRaw instanceof Map<String, Object>)) return true;

    String lastUpdatedStr = (String) ((Map<String, Object>) metaRaw).get('lastUpdated');
    if (String.isBlank(lastUpdatedStr)) return true;

    Datetime lastUpdated = parseFhirDateTime(lastUpdatedStr);
    if (lastUpdated == null) return true;

    return lastUpdated >= Datetime.now().addMonths(-12);
}

private static Medication parseSingleMedication(Map<String, Object> resource) {
    if (resource == null) return null;

    Medication med = new Medication();

    if (resource.containsKey('id')) med.MedicationId__c = (String) resource.get('id');
    if (resource.containsKey('status')) med.Status = (String) resource.get('status');

    Object codeObjRaw = resource.get('code');
    if (codeObjRaw instanceof Map<String, Object>) {
        Map<String, Object> codeObj = (Map<String, Object>) codeObjRaw;
        if (codeObj.containsKey('text')) med.Name = (String) codeObj.get('text');

        Object codingRaw = codeObj.get('coding');
        if (codingRaw instanceof List<Object>) {
            List<Object> codingList = (List<Object>) codingRaw;
            if (!codingList.isEmpty() && codingList[0] instanceof Map<String, Object>) {
                Map<String, Object> coding = (Map<String, Object>) codingList[0];
                String codeStr = (String) coding.get('code');
                if (!String.isBlank(codeStr)) {
                    try {
                        med.BatchNumber = Integer.valueOf(codeStr);
                    } catch (Exception ex) {
                        System.debug('⚠️ Could not convert code to integer: ' + codeStr);
                    }
                }
            }
        }
    }

    return med;
}

    
    ///----------Medical Administration-----------------------

public static void parseAndInsertMedicationAdministrations(String rawJson) {

    if (String.isBlank(rawJson)) {
        return;
    }

    try {

        Object deserialized = JSON.deserializeUntyped(rawJson);
        if (!(deserialized instanceof Map<String, Object>)) {
            return;
        }

        Map<String, Object> jsonData = (Map<String, Object>) deserialized;
        if (!jsonData.containsKey('resourceType')) {
            return;
        }

        List<MedicationAdministration> adminsToInsert = new List<MedicationAdministration>();

        Set<String> medFhirIds = new Set<String>();
        Set<String> adminIds = new Set<String>();

        if ('Bundle'.equals((String) jsonData.get('resourceType'))) {

            Object entriesRaw = jsonData.get('entry');
            if (!(entriesRaw instanceof List<Object>)) {
                return;
            }

            List<Object> entries = (List<Object>) entriesRaw;
            if (entries.isEmpty()) {
                return;
            }

            for (Object o : entries) {

                if (!(o instanceof Map<String, Object>)) continue;

                Map<String, Object> entry = (Map<String, Object>) o;
                Object resRaw = entry.get('resource');

                if (!(resRaw instanceof Map<String, Object>)) continue;

                Map<String, Object> res = (Map<String, Object>) resRaw;

                if (!'MedicationAdministration'.equals((String) res.get('resourceType'))) continue;

              if (!isStartDateWithin12Months(res)) {
                    System.debug('⏭️ Skipping MedicationAdministration (StartDate missing or older than 12 months): ' + res.get('id'));
                    continue;
                }

                String adminId = (String) res.get('id');
                if (!String.isBlank(adminId)) {
                    adminIds.add(adminId);
                }

                Object medRefRaw = res.get('medicationReference');

                if (medRefRaw instanceof Map<String, Object>) {

                    String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');

                    if (!String.isBlank(ref) && ref.contains('/')) {
                        medFhirIds.add(ref.split('/')[1]);
                    }
                }
            }

            Map<String, Medication> medMap = new Map<String, Medication>();

            if (!medFhirIds.isEmpty()) {

                for (Medication m : [
                    SELECT Id, MedicationId__c
                    FROM Medication
                    WHERE MedicationId__c IN :medFhirIds
                ]) {
                    medMap.put(m.MedicationId__c, m);
                }
            }

            Set<String> existingAdminIds = new Set<String>();

            if (!adminIds.isEmpty()) {

                for (MedicationAdministration ma : [
                    SELECT Id, MedicationAdministrationId__c
                    FROM MedicationAdministration
                    WHERE MedicationAdministrationId__c IN :adminIds
                ]) {
                    existingAdminIds.add(ma.MedicationAdministrationId__c);
                }
            }

            Set<String> deletedAdminIds = new Set<String>();

            if (!adminIds.isEmpty()) {

                for (Deleted_Record_Audit__c del : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE External_Id_Metriport__c IN :adminIds
                    AND Object_API_Name__c = 'MedicationAdministration'
                ]) {
                    deletedAdminIds.add(del.External_Id_Metriport__c);
                }
            }

            /* -------------------------
               Dedup key: MedicationId + StartDate + EndDate
               Fetch existing composite keys from MedicationAdministration
            -------------------------- */
            // Collect patient FHIR IDs from subject references to scope dedupe query
            Set<String> adminPatientFhirIds = new Set<String>();
            for (Object o2 : entries) {
                if (!(o2 instanceof Map<String, Object>)) continue;
                Object r2 = ((Map<String, Object>) o2).get('resource');
                if (!(r2 instanceof Map<String, Object>)) continue;
                Map<String, Object> res2 = (Map<String, Object>) r2;
                if (!'MedicationAdministration'.equals((String) res2.get('resourceType'))) continue;
                Object subjRaw = res2.get('subject');
                if (subjRaw instanceof Map<String, Object>) {
                    String ref2 = (String) ((Map<String, Object>) subjRaw).get('reference');
                    if (!String.isBlank(ref2) && ref2.contains('/')) adminPatientFhirIds.add(ref2.split('/')[1]);
                }
            }
            Set<Id> adminPatientIds = new Set<Id>();
            if (!adminPatientFhirIds.isEmpty()) {
                for (Account a : [SELECT Id FROM Account WHERE Metriport_Patient_Id__c IN :adminPatientFhirIds]) {
                    adminPatientIds.add(a.Id);
                }
            }
            Set<String> existingAdminDedupeKeys = new Set<String>();
            if (!adminPatientIds.isEmpty()) {
                for (MedicationAdministration ma : [
                    SELECT MedicationId, StartDate, EndDate
                    FROM MedicationAdministration
                    WHERE MedicationId != null
                      AND PatientId IN :adminPatientIds
                ]) {
                    String key = buildMedAdminDedupeKey(ma.MedicationId, ma.StartDate, ma.EndDate);
                    if (!String.isBlank(key)) existingAdminDedupeKeys.add(key);
                }
            }

            Set<String> inFlightAdminDedupeKeys = new Set<String>();

            for (Object o : entries) {

                if (!(o instanceof Map<String, Object>)) continue;

                Map<String, Object> entry = (Map<String, Object>) o;
                Object resRaw = entry.get('resource');

                if (!(resRaw instanceof Map<String, Object>)) continue;

                Map<String, Object> res = (Map<String, Object>) resRaw;

                if (!'MedicationAdministration'.equals((String) res.get('resourceType'))) continue;

                String adminId = (String) res.get('id');

                if (existingAdminIds.contains(adminId) || deletedAdminIds.contains(adminId)) {
                    continue;
                }

                MedicationAdministration ma =
                    parseSingleMedicationAdministration(res, medMap);

                if (ma != null) {

                    ma.MedicationAdministrationId__c = adminId;

                    // Dedup by composite key: MedicationId + StartDate + EndDate
                    String dedupeKey = buildMedAdminDedupeKey(ma.MedicationId, ma.StartDate, ma.EndDate);
                    if (!String.isBlank(dedupeKey)) {
                        if (existingAdminDedupeKeys.contains(dedupeKey) || inFlightAdminDedupeKeys.contains(dedupeKey)) {
                            System.debug('⛔ Skipping MedicationAdministration (Composite Duplicate): ' + dedupeKey);
                            continue;
                        }
                        inFlightAdminDedupeKeys.add(dedupeKey);
                    }

                    adminsToInsert.add(ma);
                }
            }

        }

        else if ('MedicationAdministration'.equals((String) jsonData.get('resourceType'))) {

            String adminId = (String) jsonData.get('id');

            if (String.isBlank(adminId)) {
                return;
            }

            List<MedicationAdministration> existing = [
                SELECT Id
                FROM MedicationAdministration
                WHERE MedicationAdministrationId__c = :adminId
                LIMIT 1
            ];

            if (!existing.isEmpty()) {
                System.debug('⛔ Duplicate MedicationAdministration skipped: ' + adminId);
                return;
            }

            List<Deleted_Record_Audit__c> deleted = [
                SELECT Id
                FROM Deleted_Record_Audit__c
                WHERE External_Id_Metriport__c = :adminId
                AND Object_API_Name__c = 'MedicationAdministration'
                LIMIT 1
            ];

            if (!deleted.isEmpty()) {
                System.debug('⛔ Deleted MedicationAdministration skipped: ' + adminId);
                return;
            }

            Map<String, Medication> medMap = new Map<String, Medication>();

            Object medRefRaw = jsonData.get('medicationReference');

            if (medRefRaw instanceof Map<String, Object>) {

                String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');

                if (!String.isBlank(ref) && ref.contains('/')) {

                    String medFhir = ref.split('/')[1];

                    List<Medication> meds = [
                        SELECT Id, MedicationId__c
                        FROM Medication
                        WHERE MedicationId__c = :medFhir
                        LIMIT 1
                    ];

                    if (!meds.isEmpty()) {
                        medMap.put(medFhir, meds[0]);
                    }
                }
            }

            MedicationAdministration ma =
                parseSingleMedicationAdministration(jsonData, medMap);

            if (ma != null) {

                ma.MedicationAdministrationId__c = adminId;
                adminsToInsert.add(ma);
            }
        }

        if (!adminsToInsert.isEmpty()) {

            Database.SaveResult[] results = Database.insert(adminsToInsert, false);

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

                    MedicationAdministration failedMa = adminsToInsert[i];

                    errorLogs.add(new Error_Log__c(
                        Object_API_Name__c    = 'MedicationAdministration',
                        Error_Message__c      = String.join(errorMessages, '\n'),
                        Record_External_Id__c = failedMa.MedicationAdministrationId__c,
                        Context__c            = 'parseAndInsertMedicationAdministrations',
                        Stack_Trace__c        = 'PatientId: ' + failedMa.PatientId +
                                                ' | MedicationAdministrationId: ' + failedMa.MedicationAdministrationId__c
                    ));
                }
            }

            if (!errorLogs.isEmpty()) {
                Database.insert(errorLogs, false);
                System.debug('⚠️ Failed MedicationAdministration inserts logged: ' + errorLogs.size());
            }

            System.debug('✅ Inserted MedicationAdministration records: ' + successCount +
                         ' | Failed: ' + (adminsToInsert.size() - successCount));

            // Consolidate into one Medication_History__c per medicine name
            Id adminPatientId = adminsToInsert.isEmpty() ? null : adminsToInsert[0].PatientId;
            if (adminPatientId != null) {
                MedicationHandler.upsertMedicationHistory(adminPatientId);
            }
        }

    }

    catch (Exception e) {

        System.debug('❌ Error parsing MedicationAdministration: ' + e.getMessage());
    }
}

/* -------------------------
   Helper: build MedicationAdministration dedupe key
-------------------------- */
private static String buildMedAdminDedupeKey(Id medicationId, Datetime startDate, Datetime endDate) {
    String medPart   = (medicationId != null) ? String.valueOf(medicationId) : '';
    String startPart = (startDate != null) ? String.valueOf(startDate) : '';
    String endPart   = (endDate   != null) ? String.valueOf(endDate)   : '';
    if (String.isBlank(medPart) && String.isBlank(startPart) && String.isBlank(endPart)) return null;
    return medPart + '|' + startPart + '|' + endPart;
}

    
private static MedicationAdministration parseSingleMedicationAdministration(
    Map<String, Object> resource,
    Map<String, Medication> medMap
) {
    if (resource == null) {
        return null;
    }

    MedicationAdministration ma = new MedicationAdministration();

    if (resource.containsKey('id')) {
        ma.MedicationAdministrationId__c = (String) resource.get('id');
    }

    Object subjectRaw = resource.get('subject');
    if (subjectRaw instanceof Map<String, Object>) {
        String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
        if (!String.isBlank(ref) && ref.contains('/')) {
            String fhirId = ref.split('/')[1];
            List<Account> acc = [
                SELECT Id
                FROM Account
                WHERE Metriport_Patient_Id__c = :fhirId
                LIMIT 1
            ];
            if (!acc.isEmpty()) {
                ma.PatientId = acc[0].Id;
            }
        }
    }

    Object medRefRaw = resource.get('medicationReference');
    if (!(medRefRaw instanceof Map<String, Object>)) {
        System.debug('⚠️ SKIPPING MedicationAdministration — no medicationReference');
        return null;
    }

    String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
    if (String.isBlank(ref) || !ref.contains('/')) {
        System.debug('⚠️ SKIPPING MedicationAdministration — invalid medication reference');
        return null;
    }

    String medFhir = ref.split('/')[1];
    if (!medMap.containsKey(medFhir)) {
        System.debug('⚠️ SKIPPING MedicationAdministration — Medication not found for FHIR: ' + medFhir);
        return null;
    }

    ma.MedicationId = medMap.get(medFhir).Id;

    Object effRaw = resource.get('effectivePeriod');
    if (effRaw instanceof Map<String, Object>) {
        Map<String, Object> eff = (Map<String, Object>) effRaw;

        if (eff.containsKey('start')) {
            ma.StartDate = parseFhirDateTime(eff.get('start'));
        }
        if (eff.containsKey('end')) {
            ma.EndDate = parseFhirDateTime(eff.get('end'));
        }
    }

    return ma;
}

		private static Datetime parseFhirDateTime(Object dtObj) {
    if (dtObj == null) return null;

    String dt = String.valueOf(dtObj).trim();
    if (String.isBlank(dt)) return null;

    dt = dt.replace(' ', 'T');

    if (dt.endsWith('Z')) {
        dt = dt.substring(0, dt.length() - 1);
    }
    if (dt.contains('+')) {
        dt = dt.substring(0, dt.indexOf('+'));
    }
    if (dt.lastIndexOf('-') > 9) {
        dt = dt.substring(0, dt.lastIndexOf('-'));
    }
    if (dt.contains('.')) {
        dt = dt.substring(0, dt.indexOf('.'));
    }
    if (dt.length() == 10) {
        dt += 'T00:00:00';
    }

    dt = dt.replace('T', ' ');

    try {
        return Datetime.valueOfGmt(dt);
    } catch (Exception e) {
        System.debug('❌ Datetime parse failed for: ' + dt + ' → ' + e.getMessage());
        return null;
    }
}
    
    private static Boolean isStartDateWithin12Months(Map<String, Object> resource) {

        if (resource == null) {
            return false;
        }
    
        Object effectiveRaw = resource.get('effectivePeriod');
    
        if (!(effectiveRaw instanceof Map<String, Object>)) {
            return false;
        }
    
        Map<String, Object> effective = (Map<String, Object>) effectiveRaw;
    
        if (!effective.containsKey('start')) {
            return false;
        }
    
        Datetime startDate = parseFhirDateTime(effective.get('start'));
    
        if (startDate == null) {
            return false;
        }
    
        Datetime twelveMonthsAgo = System.now().addMonths(-12);
    
        return startDate >= twelveMonthsAgo;
    }

    //------------------Health Condition------------
    
            public static void parseAndInsertConditions(String rawJson) {
        if (String.isBlank(rawJson)) {
            return;
        }
    
        try {
            Object deserialized = JSON.deserializeUntyped(rawJson);
            if (!(deserialized instanceof Map<String, Object>)) {
                return;
            }
    
            Map<String, Object> jsonData = (Map<String, Object>) deserialized;
            if (!jsonData.containsKey('resourceType')) {
                return;
            }
    
            List<Map<String, Object>> conditionResources =
                new List<Map<String, Object>>();
            Set<String> patientFhirIds = new Set<String>();
    
            if ('Bundle'.equals((String) jsonData.get('resourceType'))) {
    
                Object entriesRaw = jsonData.get('entry');
                if (!(entriesRaw instanceof List<Object>)) {
                    return;
                }
    
                List<Object> entries = (List<Object>) entriesRaw;
    
                for (Object o : entries) {
                    if (!(o instanceof Map<String, Object>)) continue;
    
                    Map<String, Object> entry = (Map<String, Object>) o;
                    Object resRaw = entry.get('resource');
    
                    if (!(resRaw instanceof Map<String, Object>)) continue;
    
                    Map<String, Object> res = (Map<String, Object>) resRaw;
    
                    if (!'Condition'.equals((String) res.get('resourceType'))) {
                        continue;
                    }
    
                    conditionResources.add(res);
    
                    Object subjectRaw = res.get('subject');
                    if (subjectRaw instanceof Map<String, Object>) {
                        String ref =
                            (String) ((Map<String, Object>) subjectRaw)
                                .get('reference');
    
                        if (!String.isBlank(ref) && ref.contains('/')) {
                            patientFhirIds.add(ref.split('/')[1]);
                        }
                    }
                }
    
            } else if ('Condition'.equals((String) jsonData.get('resourceType'))) {
    
                conditionResources.add(jsonData);
    
                Object subjectRaw = jsonData.get('subject');
                if (subjectRaw instanceof Map<String, Object>) {
                    String ref =
                        (String) ((Map<String, Object>) subjectRaw)
                            .get('reference');
    
                    if (!String.isBlank(ref) && ref.contains('/')) {
                        patientFhirIds.add(ref.split('/')[1]);
                    }
                }
            }
    
            if (conditionResources.isEmpty()) {
                return;
            }
    
            Map<String, Id> patientToMemberMap = new Map<String, Id>();
    
            if (!patientFhirIds.isEmpty()) {
                for (Account a : [
                    SELECT Id,Metriport_Patient_Id__c,
                           PersonContactId
                    FROM Account
                    WHERE IsPersonAccount = true
                      AND Metriport_Patient_Id__c IN :patientFhirIds
                ]) {
                    if (a.Id != null) {
                        patientToMemberMap.put(
                            a.Metriport_Patient_Id__c,
                            a.Id
                        );
                    }
                }
            }
    
                Set<String> incomingConditionIds = new Set<String>();
                
                for (Map<String, Object> res : conditionResources) {
                    if (res.containsKey('id') && res.get('id') != null) {
                        incomingConditionIds.add((String) res.get('id'));
                    }
                }
                    Set<String> existingConditionIds = new Set<String>();
                    
                    if (!incomingConditionIds.isEmpty()) {
                        for (HealthCondition mh : [
                            SELECT ConditionId__c
                            FROM HealthCondition
                            WHERE ConditionId__c IN :incomingConditionIds
                        ]) {
                            existingConditionIds.add(mh.ConditionId__c);
                        }
                    }
                    Set<String> deletedConditionIds = new Set<String>();
        
        if (!incomingConditionIds.isEmpty()) {
            for (Deleted_Record_Audit__c del : [
                SELECT External_Id_Metriport__c
                FROM Deleted_Record_Audit__c
                WHERE External_Id_Metriport__c IN :incomingConditionIds
                AND Object_API_Name__c = 'HealthCondition'
            ]) {
                deletedConditionIds.add(del.External_Id_Metriport__c);
            }
        }

        /* -------------------------
           Dedup key: ProblemName + ProblemDescription + OnsetStartDateTime
           Fetch existing composite keys from HealthCondition
        -------------------------- */
        Set<Id> condPatientIds = new Set<Id>(patientToMemberMap.values());
        Set<String> existingCondDedupeKeys = new Set<String>();
        if (!condPatientIds.isEmpty()) {
            for (HealthCondition hc : [
                SELECT ProblemName
                FROM HealthCondition
                WHERE ProblemName != null
                  AND PatientId IN :condPatientIds
            ]) {
                String key = buildConditionDedupeKey(hc.ProblemName);
                if (!String.isBlank(key)) existingCondDedupeKeys.add(key);
            }
        }

            List<HealthCondition> toInsert =
                new List<HealthCondition>();
            Set<String> inFlightCondDedupeKeys = new Set<String>();
                
            for (Map<String, Object> res : conditionResources) {
            
                String conditionId = (String) res.get('id');
            
               
                if (existingConditionIds.contains(conditionId)) {
                    continue;
                }
                if (deletedConditionIds.contains(conditionId)) {
                    continue;
                }
                
                  if (!isChronicCondition(res)) {
                    System.debug('Skipping Condition (Not Chronic): ' + conditionId);
                    continue;
                }
            
                HealthCondition mh =
                    parseSingleCondition(res, patientToMemberMap);
            
                if (mh != null) {
                    // Skip "No Data Available" condition names
                    if (!String.isBlank(mh.ProblemName) && mh.ProblemName.trim().equalsIgnoreCase('No Data Available')) {
                        System.debug('⏭️ Skipping Condition (No Data Available name): ' + conditionId);
                        continue;
                    }

                    // Dedup by composite key: ProblemName + ProblemDescription + OnsetStartDateTime
                    String dedupeKey = buildConditionDedupeKey(mh.ProblemName);
                    if (!String.isBlank(dedupeKey)) {
                        if (existingCondDedupeKeys.contains(dedupeKey) || inFlightCondDedupeKeys.contains(dedupeKey)) {
                            System.debug('⏭️ Skipping Condition (Composite Duplicate): ' + dedupeKey);
                            continue;
                        }
                        inFlightCondDedupeKeys.add(dedupeKey);
                    }
                    toInsert.add(mh);
                }
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

                        HealthCondition failedHc = toInsert[i];

                        errorLogs.add(new Error_Log__c(
                            Object_API_Name__c    = 'HealthCondition',
                            Error_Message__c      = String.join(errorMessages, '\n'),
                            Record_External_Id__c = failedHc.ConditionId__c,
                            Context__c            = 'parseAndInsertConditions',
                            Stack_Trace__c        = 'PatientId: ' + failedHc.PatientId +
                                                    ' | ConditionId: ' + failedHc.ConditionId__c
                        ));
                    }
                }

                if (!errorLogs.isEmpty()) {
                    Database.insert(errorLogs, false);
                    System.debug('⚠️ Failed HealthCondition inserts logged: ' + errorLogs.size());
                }

                System.debug('✅ Inserted HealthCondition records: ' + successCount +
                             ' | Failed: ' + (toInsert.size() - successCount));
            }
    
        } catch (Exception e) {
            System.debug(
                '❌ Error parsing Condition: ' +
                e.getMessage()
            );
        }
    }

/* -------------------------
   Helper: build Condition dedupe key
-------------------------- */
private static String buildConditionDedupeKey(String problemName) {
    String namePart  = String.isBlank(problemName) ? '' : problemName.trim().toLowerCase();

    if (String.isBlank(namePart) ) return null;
    return namePart;
}

    
                      private static HealthCondition parseSingleCondition(
            Map<String, Object> resource,
            Map<String, Id> patientToMemberMap
        ) {
            if (resource == null) {
                return null;
            }
        
            HealthCondition hc = new HealthCondition();
        
            if (resource.containsKey('id')) {
                hc.ConditionId__c = (String) resource.get('id');
            }
        
            Object codeRaw = resource.get('code');
            if (codeRaw instanceof Map<String, Object>) {
                Map<String, Object> code = (Map<String, Object>) codeRaw;
                if (code.containsKey('text')) {
                    hc.ProblemName = (String) code.get('text');
                }
            } 
        
            Object onsetRaw = resource.get('onsetPeriod');
            if (onsetRaw instanceof Map<String, Object>) {
                Map<String, Object> onset = (Map<String, Object>) onsetRaw;
        
                if (onset.containsKey('start') && onset.get('start') != null) {
                    hc.OnsetStartDateTime =
                        parseFhirDateTime(onset.get('start'));
                }
        
                if (onset.containsKey('end') && onset.get('end') != null) {
                    hc.OnsetEndDateTime =
                        parseFhirDateTime(onset.get('end'));
                }
            }
        
            Object categoryRaw = resource.get('category');
            if (categoryRaw instanceof List<Object>) {
                List<Object> categories = (List<Object>) categoryRaw;
                List<String> categoryTexts = new List<String>();
        
                for (Object o : categories) {
                    if (!(o instanceof Map<String, Object>)) continue;
        
                    Map<String, Object> cat = (Map<String, Object>) o;
                    if (cat.containsKey('text')) {
                        String text = (String) cat.get('text');
                        if (!String.isBlank(text)) {
                            categoryTexts.add(text);
                        }
                    }
                }
        
                if (!categoryTexts.isEmpty()) {
                    hc.ProblemDescription =
                        String.join(categoryTexts, '; ');
                }
            }
        
            Object clinicalStatusRaw = resource.get('clinicalStatus');
            if (clinicalStatusRaw instanceof Map<String, Object>) {
                Map<String, Object> status =
                    (Map<String, Object>) clinicalStatusRaw;
        
                Object codingRaw = status.get('coding');
                if (codingRaw instanceof List<Object>) {
                    List<Object> codings = (List<Object>) codingRaw;
        
                    if (!codings.isEmpty() &&
                        codings[0] instanceof Map<String, Object>) {
        
                        Map<String, Object> coding =
                            (Map<String, Object>) codings[0];
        
                        if (coding.containsKey('display')) {
                            hc.ConditionStatus =
                                (String) coding.get('display');
                        } else if (coding.containsKey('code')) {
                            hc.ConditionStatus =
                                (String) coding.get('code');
                        }
                    }
                }
            }
        
            Object severityRaw = resource.get('severity');
            if (severityRaw instanceof Map<String, Object>) {
                Map<String, Object> severity =
                    (Map<String, Object>) severityRaw;
        
                Object codingRaw = severity.get('coding');
                if (codingRaw instanceof List<Object>) {
                    List<Object> codings = (List<Object>) codingRaw;
        
                    if (!codings.isEmpty() &&
                        codings[0] instanceof Map<String, Object>) {
        
                        Map<String, Object> coding =
                            (Map<String, Object>) codings[0];
        
                        if (coding.containsKey('display')) {
                            hc.Severity =
                                (String) coding.get('display');
                        }
                    }
                }
            }
        
            Object subjectRaw = resource.get('subject');
            if (subjectRaw instanceof Map<String, Object>) {
                String ref =
                    (String) ((Map<String, Object>) subjectRaw)
                        .get('reference');
        
                if (!String.isBlank(ref) && ref.contains('/')) {
                    hc.PatientId =
                        patientToMemberMap.get(ref.split('/')[1]);
                }
            }
        
            return hc;
        }


    
    
      //--------------------Medication Statement ----------------------

public static void parseAndInsertMedicationStatements(String rawJson) {
    if (String.isBlank(rawJson)) return;

    try {
        Object deserialized = JSON.deserializeUntyped(rawJson);
        if (!(deserialized instanceof Map<String, Object>)) return;

        Map<String, Object> jsonData = (Map<String, Object>) deserialized;
        if (jsonData.isEmpty()) return;

        List<Map<String, Object>> medResources = new List<Map<String, Object>>();
        Set<String> patientFhirIds = new Set<String>();
        Set<String> medicationFhirIds = new Set<String>();

        if ('Bundle'.equals((String) jsonData.get('resourceType'))) {
            Object entriesRaw = jsonData.get('entry');
            if (!(entriesRaw instanceof List<Object>)) return;

            List<Object> entries = (List<Object>) entriesRaw;

            for (Object o : entries) {
                if (!(o instanceof Map<String, Object>)) continue;

                Map<String, Object> entryMap = (Map<String, Object>) o;
                Object resRaw = entryMap.get('resource');
                if (!(resRaw instanceof Map<String, Object>)) continue;

                Map<String, Object> res = (Map<String, Object>) resRaw;

                if (!'MedicationStatement'.equals((String) res.get('resourceType'))) continue;

                // Only insert active medication statements
                String msStatus = (String) res.get('status');
                if (!'active'.equalsIgnoreCase(msStatus)) {
                    System.debug('⏭️ Skipping MedicationStatement (not active): ' + res.get('id'));
                    continue;
                }

                // Filter by effectivePeriod.start — required and must be within last 12 months
                Object effPeriodRaw = res.get('effectivePeriod');
                if (!(effPeriodRaw instanceof Map<String, Object>)) {
                    System.debug('⏭️ Skipping MedicationStatement (no effectivePeriod): ' + res.get('id'));
                    continue;
                }
                Object startRaw = ((Map<String, Object>) effPeriodRaw).get('start');
                if (startRaw == null) {
                    System.debug('⏭️ Skipping MedicationStatement (no start date): ' + res.get('id'));
                    continue;
                }
                Datetime startDt = parseFhirDateTime(startRaw);
                if (startDt == null) {
                    System.debug('⏭️ Skipping MedicationStatement (unparseable start date): ' + res.get('id'));
                    continue;
                }
                if (startDt < Datetime.now().addMonths(-12)) {
                    System.debug('⏭️ Skipping MedicationStatement (start older than 12 months): ' + res.get('id'));
                    continue;
                }
                medResources.add(res);

                Object subjectRaw = res.get('subject');
                if (subjectRaw instanceof Map<String, Object>) {
                    String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
                    if (!String.isBlank(ref) && ref.contains('/')) {
                        patientFhirIds.add(ref.split('/')[1]);
                    }
                }

                Object medRefRaw = res.get('medicationReference');
                if (medRefRaw instanceof Map<String, Object>) {
                    String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
                    if (!String.isBlank(ref) && ref.contains('/')) {
                        medicationFhirIds.add(ref.split('/')[1]);
                    }
                }
            }
        }

        if (medResources.isEmpty()) return;

        Map<String, Id> patientMap = new Map<String, Id>();
        if (!patientFhirIds.isEmpty()) {
            for (Account a : [
                SELECT Id, Metriport_Patient_Id__c
                FROM Account
                WHERE Metriport_Patient_Id__c IN :patientFhirIds
            ]) {
                if (a.Metriport_Patient_Id__c != null) {
                    patientMap.put(a.Metriport_Patient_Id__c, a.Id);
                }
            }
        }

        Map<String, Id> medicationMap = new Map<String, Id>();
        Map<String, String> medicationNameMap = new Map<String, String>();
        if (!medicationFhirIds.isEmpty()) {
            for (Medication m : [
                SELECT Id, MedicationId__c, Name
                FROM Medication
                WHERE MedicationId__c IN :medicationFhirIds
            ]) {
                if (m.MedicationId__c != null) {
                    medicationMap.put(m.MedicationId__c, m.Id);
                    medicationNameMap.put(m.MedicationId__c, m.Name);
                }
            }
        }

                Set<String> incomingMedIds = new Set<String>();
        for (Map<String, Object> res : medResources) {
            if (res.containsKey('id') && res.get('id') != null) {
                incomingMedIds.add((String) res.get('id'));
            }
        }
		
        Set<String> existingMedIds = new Set<String>();
        if (!incomingMedIds.isEmpty()) {
            for (MedicationStatement ms : [
                SELECT MedicationStatementId__c
                FROM MedicationStatement
                WHERE MedicationStatementId__c IN :incomingMedIds
            ]) {
                existingMedIds.add(ms.MedicationStatementId__c);
            }
        }
        
        Set<String> deletedMedStmtIds = new Set<String>();

        if (!incomingMedIds.isEmpty()) {
            for (Deleted_Record_Audit__c del : [
                SELECT External_Id_Metriport__c
                FROM Deleted_Record_Audit__c
                WHERE External_Id_Metriport__c IN :incomingMedIds
                AND Object_API_Name__c = 'MedicationStatement'
            ]) {
                deletedMedStmtIds.add(del.External_Id_Metriport__c);
            }
        }

        /* -------------------------
           Dedup key: MedicationId + Frequency__c + Dose__c
           Fetch existing composite keys from MedicationStatement
        -------------------------- */
        Set<Id> stmtPatientIds = new Set<Id>(patientMap.values());
        Set<String> existingMedStmtDedupeKeys = new Set<String>();
        if (!stmtPatientIds.isEmpty()) {
            for (MedicationStatement ms : [
                SELECT Medication.Name
                FROM MedicationStatement
                WHERE MedicationId != null
                  AND PatientId IN :stmtPatientIds
            ]) {
                String key = buildMedStatementDedupeKey(ms.Medication.Name);
                if (!String.isBlank(key)) existingMedStmtDedupeKeys.add(key);
            }
        }

        List<MedicationStatement> medsToInsert = new List<MedicationStatement>();
        Set<String> inFlightMedStmtDedupeKeys = new Set<String>();
        
        for (Map<String, Object> res : medResources) {
            String medStmtId = (String) res.get('id');
            
            if (existingMedIds.contains(medStmtId)) continue;
             if (deletedMedStmtIds.contains(medStmtId)) continue;
        
            MedicationStatement ms = parseSingleMedicationStatement(res, patientMap, medicationMap);
            if (ms != null) {
                // Resolve medication name from FHIR reference for name-based dedup
                String medName = null;
                Object medRefRaw2 = res.get('medicationReference');
                if (medRefRaw2 instanceof Map<String, Object>) {
                    String medRef = (String) ((Map<String, Object>) medRefRaw2).get('reference');
                    if (!String.isBlank(medRef) && medRef.contains('/')) {
                        medName = medicationNameMap.get(medRef.split('/')[1]);
                    }
                }

                // Dedup by Medication Name (lowercase)
                String dedupeKey = buildMedStatementDedupeKey(medName);
                if (!String.isBlank(dedupeKey)) {
                    if (existingMedStmtDedupeKeys.contains(dedupeKey) || inFlightMedStmtDedupeKeys.contains(dedupeKey)) {
                        System.debug('⏭️ Skipping MedicationStatement (Composite Duplicate): ' + dedupeKey);
                        continue;
                    }
                    inFlightMedStmtDedupeKeys.add(dedupeKey);
                }
                medsToInsert.add(ms);
            }
        }


        if (!medsToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(medsToInsert, false);

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

                    MedicationStatement failedMs = medsToInsert[i];

                    errorLogs.add(new Error_Log__c(
                        Object_API_Name__c    = 'MedicationStatement',
                        Error_Message__c      = String.join(errorMessages, '\n'),
                        Record_External_Id__c = failedMs.MedicationStatementId__c,
                        Context__c            = 'parseAndInsertMedicationStatements',
                        Stack_Trace__c        = 'PatientId: ' + failedMs.PatientId +
                                                ' | MedicationStatementId: ' + failedMs.MedicationStatementId__c
                    ));
                }
            }

            if (!errorLogs.isEmpty()) {
                Database.insert(errorLogs, false);
                System.debug('⚠️ Failed MedicationStatement inserts logged: ' + errorLogs.size());
            }

            System.debug('✅ Inserted MedicationStatements: ' + successCount +
                         ' | Failed: ' + (medsToInsert.size() - successCount));

            // Consolidate into one Medication_History__c per medicine name
            Id stmtPatientId = medsToInsert.isEmpty() ? null : medsToInsert[0].PatientId;
            if (stmtPatientId != null) {
                MedicationHandler.upsertMedicationHistory(stmtPatientId);
            }
        }

    } catch (Exception e) {
        System.debug('❌ Error parsing MedicationStatements: ' + e.getMessage());
    }
}

/* -------------------------
   Helper: build MedicationStatement dedupe key
-------------------------- */
private static String buildMedStatementDedupeKey(String medicationName) {
    String namePart = String.isBlank(medicationName) ? '' : medicationName.trim().toLowerCase();
    if (String.isBlank(namePart)) return null;
    return namePart;
}

        

          private static MedicationStatement parseSingleMedicationStatement(
    Map<String, Object> resource,
    Map<String, Id> patientMap,
    Map<String, Id> medicationMap
) {
    if (resource == null) return null;

    MedicationStatement ms = new MedicationStatement();
    
     if (resource.containsKey('id') && resource.get('id') != null) {
                ms.MedicationStatementId__c = (String) resource.get('id');
            }

    if (resource.containsKey('status')) {
        ms.Status = (String) resource.get('status');
    }

    Object subjectRaw = resource.get('subject');
    if (subjectRaw instanceof Map<String, Object>) {
        String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
        if (!String.isBlank(ref) && ref.contains('/')) {
            ms.PatientId = patientMap.get(ref.split('/')[1]);
        }
    }

    Object medRefRaw = resource.get('medicationReference');
    if (medRefRaw instanceof Map<String, Object>) {
        String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
        if (!String.isBlank(ref) && ref.contains('/')) {
            ms.MedicationId = medicationMap.get(ref.split('/')[1]);
        }
    }

    Object effPeriodRaw = resource.get('effectivePeriod');
    if (effPeriodRaw instanceof Map<String, Object>) {
        Map<String, Object> effectivePeriod = (Map<String, Object>) effPeriodRaw;
        if (effectivePeriod.containsKey('start') && effectivePeriod.get('start') != null) {
            try {
                String startStr = String.valueOf(effectivePeriod.get('start')).replace('T', ' ').replace('Z', '');
                ms.StartDateTime = Datetime.valueOfGmt(startStr);
            } catch (Exception ex) {
                System.debug('⚠️ Could not parse effectivePeriod.start: ' + effectivePeriod.get('start'));
            }
        }
    }

    Object dosageListRaw = resource.get('dosage');
    if (dosageListRaw instanceof List<Object>) {
        List<Object> dosageList = (List<Object>) dosageListRaw;
        if (!dosageList.isEmpty()) {
            Object firstDosageRaw = dosageList[0];
            if (firstDosageRaw instanceof Map<String, Object>) {
                Map<String, Object> dosage = (Map<String, Object>) firstDosageRaw;

                if (dosage.containsKey('text')) {
                    ms.Frequency__c = (String) dosage.get('text');
                }

                Object doseAndRateRaw = dosage.get('doseAndRate');
                if (doseAndRateRaw instanceof List<Object>) {
                    List<Object> doseAndRate = (List<Object>) doseAndRateRaw;
                    if (!doseAndRate.isEmpty()) {
                        Object doseQtyRaw = ((Map<String, Object>) doseAndRate[0]).get('doseQuantity');
                        if (doseQtyRaw instanceof Map<String, Object>) {
                            Map<String, Object> doseQty = (Map<String, Object>) doseQtyRaw;
                            if (doseQty.containsKey('value') && doseQty.containsKey('unit')) {
                                ms.Dose__c = doseQty.get('value') + ' ' + (String) doseQty.get('unit');
                            }
                        }
                    }
                }
            }
        }
    }

    return ms;
}


//-----------------Surgical History -----------------

        public static void parseAndInsertProcedures(String rawJson) {
            if (String.isBlank(rawJson)) return;
        
            try {
                Object deserialized = JSON.deserializeUntyped(rawJson);
                if (!(deserialized instanceof Map<String, Object>)) return;
        
                Map<String, Object> jsonData = (Map<String, Object>) deserialized;
                if (jsonData.isEmpty()) return;
        
                List<Map<String, Object>> procedureResources = new List<Map<String, Object>>();
                Set<String> patientFhirIds = new Set<String>();
                Set<String> incomingProcedureIds = new Set<String>();
        
                Object resourceTypeObj = jsonData.get('resourceType');
                if ('Bundle'.equals((String) resourceTypeObj)) {
        
                    Object entriesRaw = jsonData.get('entry');
                    if (!(entriesRaw instanceof List<Object>)) return;
        
                    for (Object o : (List<Object>) entriesRaw) {
                        if (!(o instanceof Map<String, Object>)) continue;
        
                        Map<String, Object> entryMap = (Map<String, Object>) o;
                        Object resRaw = entryMap.get('resource');
                        if (!(resRaw instanceof Map<String, Object>)) continue;
        
                        Map<String, Object> res = (Map<String, Object>) resRaw;
                        if (!'Procedure'.equals((String) res.get('resourceType'))) continue;
        
                        procedureResources.add(res);
        
                        if (res.containsKey('id') && res.get('id') != null) {
                            incomingProcedureIds.add((String) res.get('id'));
                        }
        
                        Object subjectRaw = res.get('subject');
                        if (subjectRaw instanceof Map<String, Object>) {
                            String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
                            if (!String.isBlank(ref) && ref.contains('/')) {
                                patientFhirIds.add(ref.split('/')[1]);
                            }
                        }
                    }
                }
                else if ('Procedure'.equals((String) resourceTypeObj)) {
                    procedureResources.add(jsonData);
        
                    if (jsonData.containsKey('id') && jsonData.get('id') != null) {
                        incomingProcedureIds.add((String) jsonData.get('id'));
                    }
        
                    Object subjectRaw = jsonData.get('subject');
                    if (subjectRaw instanceof Map<String, Object>) {
                        String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
                        if (!String.isBlank(ref) && ref.contains('/')) {
                            patientFhirIds.add(ref.split('/')[1]);
                        }
                    }
                }
        
                if (procedureResources.isEmpty()) return;
        
                Map<String, Id> patientToMemberMap = new Map<String, Id>();
                if (!patientFhirIds.isEmpty()) {
                    for (Account a : [
                        SELECT Id,Metriport_Patient_Id__c, PersonContactId
                        FROM Account
                        WHERE IsPersonAccount = true
                          AND Metriport_Patient_Id__c IN :patientFhirIds
                    ]) {
                        if (a.Id != null) {
                            patientToMemberMap.put(
                                a.Metriport_Patient_Id__c,
                                a.Id
                            );
                        }
                    }
                }
        
                Set<String> existingProcedureIds = new Set<String>();
                if (!incomingProcedureIds.isEmpty()) {
                    for (HealthCareProcedure hcp : [
                        SELECT ProcedureId__c
                        FROM HealthCareProcedure
                        WHERE ProcedureId__c IN :incomingProcedureIds
                    ]) {
                        if (hcp.ProcedureId__c != null) {
                            existingProcedureIds.add(hcp.ProcedureId__c);
                        }
                    }
                }
                
                Set<String> deletedProcedureIds = new Set<String>();

                if (!incomingProcedureIds.isEmpty()) {
                
                    for (Deleted_Record_Audit__c del : [
                        SELECT External_Id_Metriport__c
                        FROM Deleted_Record_Audit__c
                        WHERE External_Id_Metriport__c IN :incomingProcedureIds
                        AND Object_API_Name__c = 'HealthCareProcedure'
                    ]) {
                
                        deletedProcedureIds.add(del.External_Id_Metriport__c);
                    }
                }

                /* -------------------------
                   Dedup key: Surgery_Name__c + Performed_Date_Time__c
                   Fetch existing composite keys from HealthCareProcedure
                -------------------------- */
                Set<Id> procPatientIds = new Set<Id>(patientToMemberMap.values());
                Set<String> existingProcDedupeKeys = new Set<String>();
                if (!procPatientIds.isEmpty()) {
                    for (HealthCareProcedure hcp : [
                        SELECT Surgery_Name__c
                        FROM HealthCareProcedure
                        WHERE  Patient__c IN :procPatientIds
                    ]) {
                        String key = buildProcedureDedupeKey(hcp.Surgery_Name__c);
                        if (!String.isBlank(key)) existingProcDedupeKeys.add(key);
                    }
                }
        
                List<HealthCareProcedure> toInsert =
                    new List<HealthCareProcedure>();
                Set<String> inFlightProcDedupeKeys = new Set<String>();
        
                for (Map<String, Object> res : procedureResources) {
        
                    String procId = (String) res.get('id');
        
                    if (!String.isBlank(procId) &&
                           (existingProcedureIds.contains(procId) ||
                            deletedProcedureIds.contains(procId))) {
                        
                            System.debug('⛔ Skipping Procedure (Duplicate/Deleted): ' + procId);
                            continue;
                        }
                    if (!isSurgeryProcedure(res)) {
                        System.debug('⛔ Skipping Procedure (Not Surgery CPT): ' + procId);
                        continue;
                    }
        
                    HealthCareProcedure hcp =
                        parseSingleProcedure(res, patientToMemberMap);
        
                    if (hcp != null) {
                        // Skip "No Data Available" surgery names
                        if (!String.isBlank(hcp.Surgery_Name__c) && hcp.Surgery_Name__c.trim().equalsIgnoreCase('No data available for this section')) {
                            System.debug('⛔ Skipping Procedure (No Data Available name): ' + procId);
                            continue;
                        }

                        // Dedup by composite key: Surgery_Name__c + Performed_Date_Time__c
                        String dedupeKey = buildProcedureDedupeKey(hcp.Surgery_Name__c);
                        if (!String.isBlank(dedupeKey)) {
                            if (existingProcDedupeKeys.contains(dedupeKey) || inFlightProcDedupeKeys.contains(dedupeKey)) {
                                System.debug('⛔ Skipping Procedure (Composite Duplicate): ' + dedupeKey);
                                continue;
                            }
                            inFlightProcDedupeKeys.add(dedupeKey);
                        }
                        toInsert.add(hcp);
                    }
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

                            HealthCareProcedure failedHcp = toInsert[i];

                            errorLogs.add(new Error_Log__c(
                                Object_API_Name__c    = 'HealthCareProcedure',
                                Error_Message__c      = String.join(errorMessages, '\n'),
                                Record_External_Id__c = failedHcp.ProcedureId__c,
                                Context__c            = 'parseAndInsertProcedures',
                                Stack_Trace__c        = 'Patient__c: ' + failedHcp.Patient__c +
                                                        ' | ProcedureId: ' + failedHcp.ProcedureId__c
                            ));
                        }
                    }

                    if (!errorLogs.isEmpty()) {
                        Database.insert(errorLogs, false);
                        System.debug('⚠️ Failed HealthCareProcedure inserts logged: ' + errorLogs.size());
                    }

                    System.debug('✅ Inserted HealthCareProcedure records: ' + successCount +
                                 ' | Failed: ' + (toInsert.size() - successCount));
                }
        
            } catch (Exception e) {
                System.debug(
                    '❌ Error parsing Procedure: ' +
                    e.getMessage()
                );
            }
        }

/* -------------------------
   Helper: build Procedure dedupe key
-------------------------- */
private static String buildProcedureDedupeKey(String surgeryName) {
    String namePart = String.isBlank(surgeryName) ? '' : surgeryName.trim().toLowerCase();

    if (String.isBlank(namePart)) return null;
    return namePart;
}

    
           private static HealthCareProcedure parseSingleProcedure(
        Map<String, Object> resource,
        Map<String, Id> patientToMemberMap
    ) {
        if (resource == null) return null;
    
        HealthCareProcedure hcp = new HealthCareProcedure();
    
        if (resource.containsKey('id') && resource.get('id') != null) {
            hcp.ProcedureId__c = (String) resource.get('id');
        }
    
        if (resource.containsKey('status') && resource.get('status') != null) {
            hcp.Status__c = (String) resource.get('status');
        }
    
        Object codeRaw = resource.get('code');
        if (codeRaw instanceof Map<String, Object>) {
            String codeText =
                (String) ((Map<String, Object>) codeRaw).get('text');
    
            if (!String.isBlank(codeText)) {
                hcp.Surgery_Name__c = codeText;
                    hcp.Name = codeText.length() > 200 ? codeText.substring(0, 200) : codeText; 
            }
        }
        
            Object categoryRaw = resource.get('category');
            
            if (categoryRaw instanceof List<Object>) {
            
                List<Object> categories =
                    (List<Object>) categoryRaw;
            
                if (!categories.isEmpty() &&
                    categories[0] instanceof Map<String, Object>) {
            
                    Map<String, Object> category =
                        (Map<String, Object>) categories[0];
            
                    String categoryText =
                        (String) category.get('text');
            
                    if (!String.isBlank(categoryText)) {
                        hcp.Note__c = categoryText;
                    }
                    else {
                        Object codingRaw =
                            category.get('coding');
            
                        if (codingRaw instanceof List<Object>) {
                            List<Object> codings =
                                (List<Object>) codingRaw;
            
                            if (!codings.isEmpty() &&
                                codings[0] instanceof Map<String, Object>) {
            
                                String display =
                                    (String)
                                        ((Map<String, Object>) codings[0])
                                            .get('display');
            
                                if (!String.isBlank(display)) {
                                    hcp.Note__c = display;
                                }
                            }
                        }
                    }
                }
            }

    
        if (resource.containsKey('performedDateTime') &&
            resource.get('performedDateTime') != null) {
    
            try {
                String dtStr =
                    String.valueOf(resource.get('performedDateTime'))
                        .replace('T', ' ')
                        .replace('Z', '');
    
                Datetime performedDt =
                    Datetime.valueOfGmt(dtStr);
    
                hcp.Performed_Date_Time__c = performedDt;
                hcp.EffectiveDate = performedDt.date();
    
            } catch (Exception ex) {
                System.debug(
                    '⚠️ Could not parse performedDateTime: ' +
                    resource.get('performedDateTime')
                );
            }
        }

        if (hcp.Performed_Date_Time__c == null &&
            resource.containsKey('effectiveDateTime') &&
            resource.get('effectiveDateTime') != null) {

            try {
                String dtStr =
                    String.valueOf(resource.get('effectiveDateTime'))
                        .replace('T', ' ')
                        .replace('Z', '');

                Datetime effectiveDt = Datetime.valueOfGmt(dtStr);

                hcp.Performed_Date_Time__c = effectiveDt;
                hcp.EffectiveDate = effectiveDt.date();

            } catch (Exception ex) {
                System.debug(
                    '⚠️ Could not parse effectiveDateTime: ' +
                    resource.get('effectiveDateTime')
                );
            }
        }
    
        Object subjectRaw = resource.get('subject');
        if (subjectRaw instanceof Map<String, Object>) {
            String ref =
                (String) ((Map<String, Object>) subjectRaw)
                    .get('reference');
    
            if (!String.isBlank(ref) && ref.contains('/')) {
                hcp.Patient__c =
                    patientToMemberMap.get(ref.split('/')[1]);
            }
        }
    
        return hcp;
    }


  //---------------Coverage(Insurance)---------------
  
       public static void parseAndInsertCoverages(String rawJson) {
        if (String.isBlank(rawJson)) return;

        try {
            Map<String, Object> jsonData =
                (Map<String, Object>) JSON.deserializeUntyped(rawJson);

            List<Map<String, Object>> coverageResources = new List<Map<String, Object>>();

            Set<String> patientFhirIds = new Set<String>();
            Set<String> organizationIds = new Set<String>();

            if ('Bundle'.equals(jsonData.get('resourceType'))) {

                List<Object> entries = (List<Object>) jsonData.get('entry');
                if (entries == null) return;

                for (Object o : entries) {
                    Map<String, Object> res =
                        (Map<String, Object>) ((Map<String, Object>) o).get('resource');

                    if (res != null && res.get('resourceType') == 'Coverage') {
                        coverageResources.add(res);
                        collectCoverageRefs(res, patientFhirIds, organizationIds);
                    }
                }

            } else if ('Coverage'.equals(jsonData.get('resourceType'))) {
                coverageResources.add(jsonData);
                collectCoverageRefs(jsonData, patientFhirIds, organizationIds);
            }

            if (coverageResources.isEmpty()) return;

            Map<String, Id> patientMap = new Map<String, Id>();
            for (Account a : [
                SELECT Id, Metriport_Patient_Id__c
                FROM Account
                WHERE Metriport_Patient_Id__c IN :patientFhirIds
            ]) {
                patientMap.put(a.Metriport_Patient_Id__c, a.Id);
            }

            Map<String, HealthcareFacility> orgAccountMap = new Map<String, HealthcareFacility>();
            for (HealthcareFacility a : [
                SELECT Id, Name, OrganizationId__c
                FROM HealthcareFacility
                WHERE OrganizationId__c IN :organizationIds
            ]) {
                orgAccountMap.put(a.OrganizationId__c, a);
            }

            Set<String> incomingCoverageIds = new Set<String>();

            for (Map<String, Object> res : coverageResources) {
                if (res.get('id') != null) {
                    incomingCoverageIds.add((String) res.get('id'));
                }
            }
            
                        Set<String> existingCoverageIds = new Set<String>();
            
            if (!incomingCoverageIds.isEmpty()) {
                for (MemberPlan mp : [
                    SELECT CoverageId__c
                    FROM MemberPlan
                    WHERE CoverageId__c IN :incomingCoverageIds
                ]) {
                    existingCoverageIds.add(mp.CoverageId__c);
                }
            }
            Set<String> deletedCoverageIds = new Set<String>();

            if (!incomingCoverageIds.isEmpty()) {
                for (Deleted_Record_Audit__c del : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE External_Id_Metriport__c IN :incomingCoverageIds
                    AND Object_API_Name__c = 'MemberPlan'
                ]) {
                    deletedCoverageIds.add(del.External_Id_Metriport__c);
                }
            }
            
                        
                        List<MemberPlan> toInsert = new List<MemberPlan>();
            
             for (Map<String, Object> res : coverageResources) {
            
                String coverageId = (String) res.get('id');
            
              
                if (existingCoverageIds.contains(coverageId) ||
                        deletedCoverageIds.contains(coverageId)) {
                    
                        System.debug('⛔ Skipping Coverage (Duplicate/Deleted): ' + coverageId);
                        continue;
                    }
            
                MemberPlan mp = parseSingleCoverage(
                    res,
                    patientMap,
                    orgAccountMap
                );
            
                if (mp != null) {
                    toInsert.add(mp);
                }
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

                        MemberPlan failedMp = toInsert[i];

                        errorLogs.add(new Error_Log__c(
                            Object_API_Name__c    = 'MemberPlan',
                            Error_Message__c      = String.join(errorMessages, '\n'),
                            Record_External_Id__c = failedMp.CoverageId__c,
                            Context__c            = 'parseAndInsertCoverages',
                            Stack_Trace__c        = 'MemberId: ' + failedMp.MemberId +
                                                    ' | CoverageId: ' + failedMp.CoverageId__c
                        ));
                    }
                }

                if (!errorLogs.isEmpty()) {
                    Database.insert(errorLogs, false);
                    System.debug('⚠️ Failed MemberPlan inserts logged: ' + errorLogs.size());
                }

                System.debug('✅ Inserted MemberPlan records: ' + successCount +
                             ' | Failed: ' + (toInsert.size() - successCount));
            }

        } catch (Exception e) {
            System.debug('❌ Error parsing Coverage: ' + e.getMessage());
        }
    }

    private static MemberPlan parseSingleCoverage(
        Map<String, Object> resource,
        Map<String, Id> patientMap,
        Map<String, HealthcareFacility> orgAccountMap
    ) {
        MemberPlan mp = new MemberPlan();

        mp.CoverageId__c = (String) resource.get('id');

        mp.Status = (String) resource.get('status');

        Map<String, Object> beneficiary =
            (Map<String, Object>) resource.get('beneficiary');

        if (beneficiary != null) {
            String ref = (String) beneficiary.get('reference');
            if (ref != null && ref.contains('/')) {
                mp.MemberId = patientMap.get(ref.split('/')[1]);
            }
        }

        List<Object> payors = (List<Object>) resource.get('payor');
        if (payors != null && !payors.isEmpty()) {
            String ref =
                (String) ((Map<String, Object>) payors[0]).get('reference');

            if (ref != null && ref.startsWith('Organization/')) {
                String orgId = ref.substring(13);
                HealthcareFacility acc = orgAccountMap.get(orgId);
                if (acc != null) {
                    mp.Name = acc.Name;
                    mp.Payer_Name__c    = acc.Name;
                }
            }
        }

        mp.PolicyId__c = (String) resource.get('subscriberId');

        return mp;
    }

    private static void collectCoverageRefs(
        Map<String, Object> res,
        Set<String> patientFhirIds,
        Set<String> organizationIds
    ) {
        Map<String, Object> beneficiary =
            (Map<String, Object>) res.get('beneficiary');

        if (beneficiary != null) {
            String ref = (String) beneficiary.get('reference');
            if (ref != null && ref.contains('/')) {
                patientFhirIds.add(ref.split('/')[1]);
            }
        }

        List<Object> payors = (List<Object>) res.get('payor');
        if (payors != null && !payors.isEmpty()) {
            String ref =
                (String) ((Map<String, Object>) payors[0]).get('reference');
            if (ref != null && ref.startsWith('Organization/')) {
                organizationIds.add(ref.substring(13));
            }
        }
    }
    
        private static Boolean isSurgeryProcedure(Map<String, Object> resource) {
        Object codeRaw = resource.get('code');

        // No code block at all — allow through
        if (!(codeRaw instanceof Map<String, Object>)) return true;

        Object codingListRaw = ((Map<String, Object>) codeRaw).get('coding');

        // code block exists but has no coding array — allow through
        if (!(codingListRaw instanceof List<Object>)) return true;

        List<Object> codingList = (List<Object>) codingListRaw;

        // Empty coding array — allow through
        if (codingList.isEmpty()) return true;

        // Has coding entries — check if any qualify as surgery
        // If none of the codings are parseable integer CPT codes, allow through
        Boolean hasParseableCode = false;

        for (Object codingObj : codingList) {
            if (!(codingObj instanceof Map<String, Object>)) continue;

            String codeStr = (String) ((Map<String, Object>) codingObj).get('code');
            if (String.isBlank(codeStr)) continue;

            String systems = (String) ((Map<String, Object>) codingObj).get('system');

            if (systems != null && systems.containsIgnoreCase('snomed')) continue;

            Integer codeInt;
            try {
                codeInt = Integer.valueOf(codeStr);
            } catch (Exception e) {
                // Non-numeric code — not a CPT code, skip this coding entry
                continue;
            }

            // Has at least one parseable integer code — apply surgery range filter
            hasParseableCode = true;
            if (isInSurgeryRange(codeInt)) return true;
        }

        // If no parseable integer CPT codes found at all, allow through
        if (!hasParseableCode) return true;

        // Had CPT codes but none were in surgery range — skip
        return false;
    }
    
    private static Boolean isInSurgeryRange(Integer code) {
        Integer[][] surgeryRanges = new Integer[][] {
            new Integer[]{ 10021, 10022 },
            new Integer[]{ 10030, 10036 },
            new Integer[]{ 11000, 11047 },
            new Integer[]{ 11055, 11057 },
            new Integer[]{ 11100, 11107 },
            new Integer[]{ 11200, 11201 },
            new Integer[]{ 11400, 11471 },
            new Integer[]{ 11600, 11646 },
            new Integer[]{ 12001, 12057 },
            new Integer[]{ 13100, 13160 },
            new Integer[]{ 20200, 20999 },
            new Integer[]{ 21010, 21499 },
            new Integer[]{ 22010, 22899 },
            new Integer[]{ 23000, 23929 },
            new Integer[]{ 24000, 24999 },
            new Integer[]{ 25000, 25999 },
            new Integer[]{ 26010, 26989 },
            new Integer[]{ 27000, 27299 },
            new Integer[]{ 27301, 27599 },
            new Integer[]{ 27600, 27899 },
            new Integer[]{ 28001, 28899 },
            new Integer[]{ 30000, 30999 },
            new Integer[]{ 31000, 31899 },
            new Integer[]{ 32035, 32999 },
            new Integer[]{ 33010, 33999 },
            new Integer[]{ 34001, 34834 },
            new Integer[]{ 40490, 40799 },
            new Integer[]{ 41000, 41599 },
            new Integer[]{ 42000, 42999 },
            new Integer[]{ 43020, 43499 },
            new Integer[]{ 43500, 43999 },
            new Integer[]{ 44005, 44799 },
            new Integer[]{ 45000, 45999 },
            new Integer[]{ 46020, 46999 },
            new Integer[]{ 47000, 47399 },
            new Integer[]{ 47400, 47999 },
            new Integer[]{ 48000, 48999 },
            new Integer[]{ 49000, 49999 },
            new Integer[]{ 50010, 50593 },
            new Integer[]{ 50600, 50980 },
            new Integer[]{ 51020, 51999 },
            new Integer[]{ 52000, 52700 },
            new Integer[]{ 53000, 53899 },
            new Integer[]{ 54000, 54699 },
            new Integer[]{ 55000, 55899 },
            new Integer[]{ 56405, 56821 },
            new Integer[]{ 57000, 57426 },
            new Integer[]{ 58100, 58579 },
            new Integer[]{ 58600, 58770 }
        };
    
        for (Integer[] range : surgeryRanges) {
            if (code >= range[0] && code <= range[1]) return true;
        }
        return false;
    }
        
    private static Boolean isChronicCondition(Map<String, Object> resource) {
        Object extListRaw = resource.get('extension');
        if (!(extListRaw instanceof List<Object>)) return false;
    
        for (Object extObj : (List<Object>) extListRaw) {
            if (!(extObj instanceof Map<String, Object>)) continue;
            Map<String, Object> ext = (Map<String, Object>) extObj;
    
            String url = (String) ext.get('url');
            if (!'http://hl7.org/fhir/StructureDefinition/condition-related'.equals(url)) continue;
    
            Object valueCodingRaw = ext.get('valueCoding');
            if (!(valueCodingRaw instanceof Map<String, Object>)) continue;
    
            Map<String, Object> valueCoding = (Map<String, Object>) valueCodingRaw;
            String systems = (String) valueCoding.get('system');
            String code   = (String) valueCoding.get('code');
    
            if ('https://public.metriport.com/fhir/StructureDefinition/condition-chronicity.json'
                    .equals(systems) && 'C'.equals(code)) {
                return true;
            }
        }
        return false;
    }
}