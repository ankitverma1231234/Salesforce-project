public without sharing class MedicationHandler {

    /* -------------------------
       Helper: meta.lastUpdated 12-month gate
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

    /* -------------------------
       Helper: parse FHIR datetime string
    -------------------------- */
    private static Datetime parseFhirDateTime(Object dtObj) {
        if (dtObj == null) return null;

        String dt = String.valueOf(dtObj).trim();
        if (String.isBlank(dt)) return null;

        dt = dt.replace(' ', 'T');
        if (dt.endsWith('Z'))             dt = dt.substring(0, dt.length() - 1);
        if (dt.contains('+'))             dt = dt.substring(0, dt.indexOf('+'));
        if (dt.lastIndexOf('-') > 9)      dt = dt.substring(0, dt.lastIndexOf('-'));
        if (dt.contains('.'))             dt = dt.substring(0, dt.indexOf('.'));
        if (dt.length() == 10)            dt += 'T00:00:00';

        dt = dt.replace('T', ' ');

        try {
            return Datetime.valueOfGmt(dt);
        } catch (Exception e) {
            System.debug('❌ Datetime parse failed: ' + dt + ' → ' + e.getMessage());
            return null;
        }
    }

    /* -------------------------
       Helper: Dispense dedupe key — MedicationId + DispensedDateTime
    -------------------------- */
    private static String buildDispenseDedupeKey(Id medicationId, Datetime dispensedDt) {
        String medPart = (medicationId != null) ? String.valueOf(medicationId) : '';
        String dtPart  = (dispensedDt  != null) ? String.valueOf(dispensedDt)  : '';
        if (String.isBlank(medPart) && String.isBlank(dtPart)) return null;
        return medPart + '|' + dtPart;
    }

    /* -------------------------
       Helper: Request dedupe key — MedicationId
    -------------------------- */
    private static String buildRequestDedupeKey(Id medicationId) {
        if (medicationId == null) return null;
        return String.valueOf(medicationId);
    }

    /* =========================================================
       Medication Dispense
    ========================================================= */
    public static void parseAndInsertMedicationDispenses(String rawJson) {
        if (String.isBlank(rawJson)) return;

        try {
            Object deserialized = JSON.deserializeUntyped(rawJson);
            if (!(deserialized instanceof Map<String, Object>)) return;

            Map<String, Object> jsonData = (Map<String, Object>) deserialized;
            if (jsonData.isEmpty()) return;

            List<Map<String, Object>> dispenseResources = new List<Map<String, Object>>();
            Set<String> patientFhirIds    = new Set<String>();
            Set<String> medicationFhirIds = new Set<String>();

            if ('Bundle'.equals((String) jsonData.get('resourceType'))) {
                Object entriesRaw = jsonData.get('entry');
                if (!(entriesRaw instanceof List<Object>)) return;

                for (Object o : (List<Object>) entriesRaw) {
                    if (!(o instanceof Map<String, Object>)) continue;

                    Object resRaw = ((Map<String, Object>) o).get('resource');
                    if (!(resRaw instanceof Map<String, Object>)) continue;

                    Map<String, Object> res = (Map<String, Object>) resRaw;
                    if (!'MedicationDispense'.equals((String) res.get('resourceType'))) continue;

                    if (!isWithin12Months(res)) {
                        System.debug('⏭️ Skipping MedicationDispense (older than 12 months): ' + res.get('id'));
                        continue;
                    }

                    dispenseResources.add(res);

                    Object subjectRaw = res.get('subject');
                    if (subjectRaw instanceof Map<String, Object>) {
                        String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
                        if (!String.isBlank(ref) && ref.contains('/')) patientFhirIds.add(ref.split('/')[1]);
                    }

                    Object medRefRaw = res.get('medicationReference');
                    if (medRefRaw instanceof Map<String, Object>) {
                        String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
                        if (!String.isBlank(ref) && ref.contains('/')) medicationFhirIds.add(ref.split('/')[1]);
                    }
                }
            }

            if (dispenseResources.isEmpty()) return;

            Map<String, Id> patientMap = new Map<String, Id>();
            if (!patientFhirIds.isEmpty()) {
                for (Account a : [
                    SELECT Id, Metriport_Patient_Id__c
                    FROM Account
                    WHERE Metriport_Patient_Id__c IN :patientFhirIds
                ]) {
                    if (a.Metriport_Patient_Id__c != null) patientMap.put(a.Metriport_Patient_Id__c, a.Id);
                }
            }

            Map<String, Id> medicationMap = new Map<String, Id>();
            if (!medicationFhirIds.isEmpty()) {
                for (Medication m : [
                    SELECT Id, MedicationId__c
                    FROM Medication
                    WHERE MedicationId__c IN :medicationFhirIds
                ]) {
                    if (m.MedicationId__c != null) medicationMap.put(m.MedicationId__c, m.Id);
                }
            }

            /* FHIR-ID dedup */
            Set<String> incomingDispenseIds = new Set<String>();
            for (Map<String, Object> res : dispenseResources) {
                if (res.get('id') != null) incomingDispenseIds.add((String) res.get('id'));
            }

            Set<String> existingDispenseIds = new Set<String>();
            if (!incomingDispenseIds.isEmpty()) {
                for (MedicationDispense md : [
                    SELECT MedicationDispenseId__c
                    FROM MedicationDispense
                    WHERE MedicationDispenseId__c IN :incomingDispenseIds
                ]) {
                    existingDispenseIds.add(md.MedicationDispenseId__c);
                }
            }

            Set<String> deletedDispenseIds = new Set<String>();
            if (!incomingDispenseIds.isEmpty()) {
                for (Deleted_Record_Audit__c audit : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE External_Id_Metriport__c IN :incomingDispenseIds
                      AND Object_API_Name__c = 'MedicationDispense'
                ]) {
                    deletedDispenseIds.add(audit.External_Id_Metriport__c);
                }
            }

            /* Composite dedupe key: MedicationId + DispensedDateTime */
            Set<Id> dispensePatientIds = new Set<Id>(patientMap.values());
            Set<String> existingDispenseDedupeKeys = new Set<String>();
            if (!dispensePatientIds.isEmpty()) {
                for (MedicationDispense md : [
                    SELECT MedicationId, DispensedDateTime
                    FROM MedicationDispense
                    WHERE MedicationId != null
                      AND PatientId IN :dispensePatientIds
                ]) {
                    String key = buildDispenseDedupeKey(md.MedicationId, md.DispensedDateTime);
                    if (!String.isBlank(key)) existingDispenseDedupeKeys.add(key);
                }
            }

            List<MedicationDispense> dispensesToInsert = new List<MedicationDispense>();
            Set<String> inFlightDispenseDedupeKeys     = new Set<String>();

            for (Map<String, Object> res : dispenseResources) {
                String dispenseId = (String) res.get('id');

                if (existingDispenseIds.contains(dispenseId) || deletedDispenseIds.contains(dispenseId)) {
                    System.debug('⏭️ Skipping MedicationDispense (Duplicate/Deleted): ' + dispenseId);
                    continue;
                }

                MedicationDispense md = parseSingleMedicationDispense(res, patientMap, medicationMap);
                if (md == null) continue;

                String dedupeKey = buildDispenseDedupeKey(md.MedicationId, md.DispensedDateTime);
                if (!String.isBlank(dedupeKey)) {
                    if (existingDispenseDedupeKeys.contains(dedupeKey) || inFlightDispenseDedupeKeys.contains(dedupeKey)) {
                        System.debug('⏭️ Skipping MedicationDispense (Composite Duplicate): ' + dedupeKey);
                        continue;
                    }
                    inFlightDispenseDedupeKeys.add(dedupeKey);
                }

                dispensesToInsert.add(md);
            }

            if (!dispensesToInsert.isEmpty()) {
                Database.SaveResult[] results = Database.insert(dispensesToInsert, false);

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
                        MedicationDispense failedMd = dispensesToInsert[i];
                        errorLogs.add(new Error_Log__c(
                            Object_API_Name__c    = 'MedicationDispense',
                            Error_Message__c      = String.join(errorMessages, '\n'),
                            Record_External_Id__c = failedMd.MedicationDispenseId__c,
                            Context__c            = 'parseAndInsertMedicationDispenses',
                            Stack_Trace__c        = 'PatientId: ' + failedMd.PatientId +
                                                    ' | DispenseId: ' + failedMd.MedicationDispenseId__c
                        ));
                    }
                }

                if (!errorLogs.isEmpty()) {
                    Database.insert(errorLogs, false);
                    System.debug('⚠️ Failed MedicationDispense inserts logged: ' + errorLogs.size());
                }

                System.debug('✅ Inserted MedicationDispense records: ' + successCount +
                             ' | Failed: ' + (dispensesToInsert.size() - successCount));
            }

        } catch (Exception e) {
            System.debug('❌ Error parsing MedicationDispenses: ' + e.getMessage());
        }
    }

    private static MedicationDispense parseSingleMedicationDispense(
        Map<String, Object> resource,
        Map<String, Id> patientMap,
        Map<String, Id> medicationMap
    ) {
        if (resource == null) return null;

        MedicationDispense md = new MedicationDispense();

        if (resource.containsKey('id') && resource.get('id') != null) {
            md.MedicationDispenseId__c = (String) resource.get('id');
        }

        if (resource.containsKey('status')) {
            md.Status = (String) resource.get('status');
        }

        Object subjectRaw = resource.get('subject');
        if (subjectRaw instanceof Map<String, Object>) {
            String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
            if (!String.isBlank(ref) && ref.contains('/')) {
                md.PatientId = patientMap.get(ref.split('/')[1]);
            }
        }

        Object medRefRaw = resource.get('medicationReference');
        if (medRefRaw instanceof Map<String, Object>) {
            String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
            if (!String.isBlank(ref) && ref.contains('/')) {
                md.MedicationId = medicationMap.get(ref.split('/')[1]);
            }
        }

        Object quantityRaw = resource.get('quantity');
        if (quantityRaw instanceof Map<String, Object>) {
            Map<String, Object> quantity = (Map<String, Object>) quantityRaw;
            if (quantity.containsKey('value') && quantity.containsKey('unit')) {
                md.Quantity__c = quantity.get('value') + ' ' + (String) quantity.get('unit');
            }
        }

        if (resource.containsKey('whenHandedOver') && resource.get('whenHandedOver') != null) {
            try {
                String handedOverStr = String.valueOf(resource.get('whenHandedOver'))
                    .replace('T', ' ')
                    .replace('Z', '')
                    .left(19);
                md.DispensedDateTime = Datetime.valueOfGmt(handedOverStr);
            } catch (Exception ex) {
                System.debug('⚠️ Could not parse whenHandedOver: ' + resource.get('whenHandedOver'));
            }
        }

        Object daysSupplyRaw = resource.get('daysSupply');
        if (daysSupplyRaw instanceof Map<String, Object>) {
            Map<String, Object> daysSupply = (Map<String, Object>) daysSupplyRaw;
            if (daysSupply.containsKey('value') && daysSupply.containsKey('unit')) {
                md.Days_Supply__c = daysSupply.get('value') + ' ' + (String) daysSupply.get('unit');
            }
        }

        return md;
    }

    /* =========================================================
       Medication Request
    ========================================================= */
    public static void parseAndInsertMedicationRequests(String rawJson) {
        if (String.isBlank(rawJson)) return;

        try {
            Object deserialized = JSON.deserializeUntyped(rawJson);
            if (!(deserialized instanceof Map<String, Object>)) return;

            Map<String, Object> jsonData = (Map<String, Object>) deserialized;
            if (jsonData.isEmpty()) return;

            List<Map<String, Object>> requestResources  = new List<Map<String, Object>>();
            Set<String> patientFhirIds       = new Set<String>();
            Set<String> medicationFhirIds    = new Set<String>();
            Set<String> organizationFhirIds  = new Set<String>();

            if ('Bundle'.equals((String) jsonData.get('resourceType'))) {
                Object entriesRaw = jsonData.get('entry');
                if (!(entriesRaw instanceof List<Object>)) return;

                for (Object o : (List<Object>) entriesRaw) {
                    if (!(o instanceof Map<String, Object>)) continue;

                    Object resRaw = ((Map<String, Object>) o).get('resource');
                    if (!(resRaw instanceof Map<String, Object>)) continue;

                    Map<String, Object> res = (Map<String, Object>) resRaw;
                    if (!'MedicationRequest'.equals((String) res.get('resourceType'))) continue;

                    if (!isWithin12Months(res)) {
                        System.debug('⏭️ Skipping MedicationRequest (older than 12 months): ' + res.get('id'));
                        continue;
                    }

                    requestResources.add(res);

                    Object subjectRaw = res.get('subject');
                    if (subjectRaw instanceof Map<String, Object>) {
                        String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
                        if (!String.isBlank(ref) && ref.contains('/')) patientFhirIds.add(ref.split('/')[1]);
                    }

                    Object medRefRaw = res.get('medicationReference');
                    if (medRefRaw instanceof Map<String, Object>) {
                        String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
                        if (!String.isBlank(ref) && ref.contains('/')) medicationFhirIds.add(ref.split('/')[1]);
                    }

                    Object performerRaw = res.get('performer');
                    if (performerRaw instanceof Map<String, Object>) {
                        String ref = (String) ((Map<String, Object>) performerRaw).get('reference');
                        if (!String.isBlank(ref) && ref.contains('/')) organizationFhirIds.add(ref.split('/')[1]);
                    }
                }
            }

            if (requestResources.isEmpty()) return;

            Map<String, Id> patientMap = new Map<String, Id>();
            if (!patientFhirIds.isEmpty()) {
                for (Account a : [
                    SELECT Id, Metriport_Patient_Id__c
                    FROM Account
                    WHERE Metriport_Patient_Id__c IN :patientFhirIds
                ]) {
                    if (a.Metriport_Patient_Id__c != null) patientMap.put(a.Metriport_Patient_Id__c, a.Id);
                }
            }

            Map<String, Id> medicationMap = new Map<String, Id>();
            if (!medicationFhirIds.isEmpty()) {
                for (Medication m : [
                    SELECT Id, MedicationId__c
                    FROM Medication
                    WHERE MedicationId__c IN :medicationFhirIds
                ]) {
                    if (m.MedicationId__c != null) medicationMap.put(m.MedicationId__c, m.Id);
                }
            }

            Map<String, Id> organizationMap = new Map<String, Id>();
            if (!organizationFhirIds.isEmpty()) {
                for (HealthcareFacility hp : [
                    SELECT Id, OrganizationId__c
                    FROM HealthcareFacility
                    WHERE OrganizationId__c IN :organizationFhirIds
                ]) {
                    if (hp.OrganizationId__c != null) organizationMap.put(hp.OrganizationId__c, hp.Id);
                }
            }

            /* FHIR-ID dedup */
            Set<String> incomingRequestIds = new Set<String>();
            for (Map<String, Object> res : requestResources) {
                if (res.get('id') != null) incomingRequestIds.add((String) res.get('id'));
            }

            Set<String> existingRequestIds = new Set<String>();
            if (!incomingRequestIds.isEmpty()) {
                for (MedicationRequest mr : [
                    SELECT MedicationRequestId__c
                    FROM MedicationRequest
                    WHERE MedicationRequestId__c IN :incomingRequestIds
                ]) {
                    existingRequestIds.add(mr.MedicationRequestId__c);
                }
            }

            Set<String> deletedRequestIds = new Set<String>();
            if (!incomingRequestIds.isEmpty()) {
                for (Deleted_Record_Audit__c del : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE Object_API_Name__c = 'MedicationRequest'
                      AND External_Id_Metriport__c IN :incomingRequestIds
                ]) {
                    deletedRequestIds.add(del.External_Id_Metriport__c);
                }
            }

            /* Composite dedupe key: MedicationId */
            Set<Id> requestPatientIds = new Set<Id>(patientMap.values());
            Set<String> existingRequestDedupeKeys = new Set<String>();
            if (!requestPatientIds.isEmpty()) {
                for (MedicationRequest mr : [
                    SELECT MedicationId
                    FROM MedicationRequest
                    WHERE MedicationId != null
                      AND PatientId IN :requestPatientIds
                ]) {
                    String key = buildRequestDedupeKey(mr.MedicationId);
                    if (!String.isBlank(key)) existingRequestDedupeKeys.add(key);
                }
            }

            List<MedicationRequest> requestsToInsert     = new List<MedicationRequest>();
            Set<String> inFlightRequestDedupeKeys        = new Set<String>();

            for (Map<String, Object> res : requestResources) {
                String requestId = (String) res.get('id');

                if (existingRequestIds.contains(requestId) || deletedRequestIds.contains(requestId)) {
                    System.debug('⏭️ Skipping MedicationRequest (Duplicate/Deleted): ' + requestId);
                    continue;
                }

                MedicationRequest mr = parseSingleMedicationRequest(res, patientMap, medicationMap, organizationMap);
                if (mr == null) continue;

                String dedupeKey = buildRequestDedupeKey(mr.MedicationId);
                if (!String.isBlank(dedupeKey)) {
                    if (existingRequestDedupeKeys.contains(dedupeKey) || inFlightRequestDedupeKeys.contains(dedupeKey)) {
                        System.debug('⏭️ Skipping MedicationRequest (Composite Duplicate): ' + dedupeKey);
                        continue;
                    }
                    inFlightRequestDedupeKeys.add(dedupeKey);
                }

                requestsToInsert.add(mr);
            }

            if (!requestsToInsert.isEmpty()) {
                Database.SaveResult[] results = Database.insert(requestsToInsert, false);

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
                        MedicationRequest failedMr = requestsToInsert[i];
                        errorLogs.add(new Error_Log__c(
                            Object_API_Name__c    = 'MedicationRequest',
                            Error_Message__c      = String.join(errorMessages, '\n'),
                            Record_External_Id__c = failedMr.MedicationRequestId__c,
                            Context__c            = 'parseAndInsertMedicationRequests',
                            Stack_Trace__c        = 'PatientId: ' + failedMr.PatientId +
                                                    ' | RequestId: ' + failedMr.MedicationRequestId__c
                        ));
                    }
                }

                if (!errorLogs.isEmpty()) {
                    Database.insert(errorLogs, false);
                    System.debug('⚠️ Failed MedicationRequest inserts logged: ' + errorLogs.size());
                }

                System.debug('✅ Inserted MedicationRequest records: ' + successCount +
                             ' | Failed: ' + (requestsToInsert.size() - successCount));
            }

        } catch (Exception e) {
            System.debug('❌ Error parsing MedicationRequests: ' + e.getMessage());
        }
    }

    private static MedicationRequest parseSingleMedicationRequest(
        Map<String, Object> resource,
        Map<String, Id> patientMap,
        Map<String, Id> medicationMap,
        Map<String, Id> organizationMap
    ) {
        if (resource == null) return null;

        MedicationRequest mr = new MedicationRequest();

        if (resource.containsKey('id') && resource.get('id') != null) {
            mr.MedicationRequestId__c = (String) resource.get('id');
        }

        if (resource.containsKey('status')) {
            mr.Status = (String) resource.get('status');
        }

        mr.Type = 'Order';

        Object subjectRaw = resource.get('subject');
        if (subjectRaw instanceof Map<String, Object>) {
            String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
            if (!String.isBlank(ref) && ref.contains('/')) {
                mr.PatientId = patientMap.get(ref.split('/')[1]);
            }
        }

        Object medRefRaw = resource.get('medicationReference');
        if (medRefRaw instanceof Map<String, Object>) {
            String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
            if (!String.isBlank(ref) && ref.contains('/')) {
                mr.MedicationId = medicationMap.get(ref.split('/')[1]);
            }
        }

        Object requesterRaw = resource.get('requester');
        if (requesterRaw instanceof Map<String, Object>) {
            String display = (String) ((Map<String, Object>) requesterRaw).get('display');
            if (!String.isBlank(display)) {
                mr.Requester_Name__c = display;
            }
        }

        Object performerRaw = resource.get('performer');
        if (performerRaw instanceof Map<String, Object>) {
            String ref = (String) ((Map<String, Object>) performerRaw).get('reference');
            if (!String.isBlank(ref) && ref.contains('/')) {
                mr.Performer__c = organizationMap.get(ref.split('/')[1]);
            }
        }

        return mr;
    }
}