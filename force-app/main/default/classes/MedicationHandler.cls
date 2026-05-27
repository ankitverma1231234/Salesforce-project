public without sharing class MedicationHandler {
    
    public static void parseAndInsertMedicationDispenses(String rawJson) {
    if (String.isBlank(rawJson)) return;

    try {
        Object deserialized = JSON.deserializeUntyped(rawJson);
        if (!(deserialized instanceof Map<String, Object>)) return;

        Map<String, Object> jsonData = (Map<String, Object>) deserialized;
        if (jsonData.isEmpty()) return;

        List<Map<String, Object>> dispenseResources = new List<Map<String, Object>>();
        Set<String> patientFhirIds = new Set<String>();
        Set<String> medicationFhirIds = new Set<String>();

        /* -------------------------
           Collect resources + IDs
        -------------------------- */
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

                if (!'MedicationDispense'.equals((String) res.get('resourceType'))) continue;

                dispenseResources.add(res);

                // Patient
                Object subjectRaw = res.get('subject');
                if (subjectRaw instanceof Map<String, Object>) {
                    String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
                    if (!String.isBlank(ref) && ref.contains('/')) {
                        patientFhirIds.add(ref.split('/')[1]);
                    }
                }

                // Medication
                Object medRefRaw = res.get('medicationReference');
                if (medRefRaw instanceof Map<String, Object>) {
                    String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
                    if (!String.isBlank(ref) && ref.contains('/')) {
                        medicationFhirIds.add(ref.split('/')[1]);
                    }
                }
            }
        }

        if (dispenseResources.isEmpty()) return;

        /* -------------------------
           Query Patients & Medications
        -------------------------- */
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
        if (!medicationFhirIds.isEmpty()) {
            for (Medication m : [
                SELECT Id, MedicationId__c
                FROM Medication
                WHERE MedicationId__c IN :medicationFhirIds
            ]) {
                if (m.MedicationId__c != null) {
                    medicationMap.put(m.MedicationId__c, m.Id);
                }
            }
        }

        /* -------------------------
           Deduplicate against existing records
        -------------------------- */
        Set<String> incomingDispenseIds = new Set<String>();
        for (Map<String, Object> res : dispenseResources) {
            if (res.containsKey('id') && res.get('id') != null) {
                incomingDispenseIds.add((String) res.get('id'));
            }
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
        

        /* -------------------------
           Build MedicationDispense records
        -------------------------- */
        List<MedicationDispense> dispensesToInsert = new List<MedicationDispense>();

        for (Map<String, Object> res : dispenseResources) {
            String dispenseId = (String) res.get('id');

            // Skip if record already exists
            if (existingDispenseIds.contains(dispenseId)) continue;
            
            if (deletedDispenseIds.contains(dispenseId)) {
                System.debug('⏭️ Skipping deleted MedicationDispense record with ID: ' + dispenseId);
                continue;
            }

            MedicationDispense md = parseSingleMedicationDispense(res, patientMap, medicationMap);
            if (md != null) dispensesToInsert.add(md);
        }

        if (!dispensesToInsert.isEmpty()) {
            Database.insert(dispensesToInsert, false);
            System.debug('✅ Inserted MedicationDispenses: ' + dispensesToInsert.size());
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

    /* FHIR ID */
    if (resource.containsKey('id') && resource.get('id') != null) {
        md.MedicationDispenseId__c = (String) resource.get('id');
    }

    /* Status */
    if (resource.containsKey('status')) {
        md.Status = (String) resource.get('status');
    }

    /* Patient */
    Object subjectRaw = resource.get('subject');
    if (subjectRaw instanceof Map<String, Object>) {
        String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
        if (!String.isBlank(ref) && ref.contains('/')) {
            md.PatientId = patientMap.get(ref.split('/')[1]);
        }
    }

    /* Medication */
    Object medRefRaw = resource.get('medicationReference');
    if (medRefRaw instanceof Map<String, Object>) {
        String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
        if (!String.isBlank(ref) && ref.contains('/')) {
            md.MedicationId = medicationMap.get(ref.split('/')[1]);
        }
    }

    /* Quantity → Quantity__c */
    Object quantityRaw = resource.get('quantity');
    if (quantityRaw instanceof Map<String, Object>) {
        Map<String, Object> quantity = (Map<String, Object>) quantityRaw;
        if (quantity.containsKey('value') && quantity.containsKey('unit')) {
            md.Quantity__c = quantity.get('value') + ' ' + (String) quantity.get('unit');
        }
    }

    /* whenHandedOver → DispensedDateTime */
    if (resource.containsKey('whenHandedOver') && resource.get('whenHandedOver') != null) {
        try {
            String handedOverStr = String.valueOf(resource.get('whenHandedOver'))
                .replace('T', ' ')
                .replace('Z', '')
                .left(19); // trim milliseconds if present e.g. .000
            md.DispensedDateTime = Datetime.valueOfGmt(handedOverStr);
        } catch (Exception ex) {
            System.debug('⚠️ Could not parse whenHandedOver: ' + resource.get('whenHandedOver'));
        }
    }

    /* daysSupply → Days_Supply__c */
    Object daysSupplyRaw = resource.get('daysSupply');
    if (daysSupplyRaw instanceof Map<String, Object>) {
        Map<String, Object> daysSupply = (Map<String, Object>) daysSupplyRaw;
        if (daysSupply.containsKey('value') && daysSupply.containsKey('unit')) {
            md.Days_Supply__c = daysSupply.get('value') + ' ' + (String) daysSupply.get('unit');
        }
    }

    return md;
}
    
    public static void parseAndInsertMedicationRequests(String rawJson) {
    if (String.isBlank(rawJson)) return;

    try {
        Object deserialized = JSON.deserializeUntyped(rawJson);
        if (!(deserialized instanceof Map<String, Object>)) return;

        Map<String, Object> jsonData = (Map<String, Object>) deserialized;
        if (jsonData.isEmpty()) return;

        List<Map<String, Object>> requestResources = new List<Map<String, Object>>();
        Set<String> patientFhirIds = new Set<String>();
        Set<String> medicationFhirIds = new Set<String>();
        Set<String> organizationFhirIds = new Set<String>();

        /* -------------------------
           Collect resources + IDs
        -------------------------- */
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

                if (!'MedicationRequest'.equals((String) res.get('resourceType'))) continue;

                requestResources.add(res);

                // Patient
                Object subjectRaw = res.get('subject');
                if (subjectRaw instanceof Map<String, Object>) {
                    String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
                    if (!String.isBlank(ref) && ref.contains('/')) {
                        patientFhirIds.add(ref.split('/')[1]);
                    }
                }

                // Medication
                Object medRefRaw = res.get('medicationReference');
                if (medRefRaw instanceof Map<String, Object>) {
                    String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
                    if (!String.isBlank(ref) && ref.contains('/')) {
                        medicationFhirIds.add(ref.split('/')[1]);
                    }
                }

                // Performer Organization
                Object performerRaw = res.get('performer');
                if (performerRaw instanceof Map<String, Object>) {
                    String ref = (String) ((Map<String, Object>) performerRaw).get('reference');
                    if (!String.isBlank(ref) && ref.contains('/')) {
                        organizationFhirIds.add(ref.split('/')[1]);
                    }
                }
            }
        }

        if (requestResources.isEmpty()) return;

        /* -------------------------
           Query Patients, Medications & Organizations
        -------------------------- */
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
        if (!medicationFhirIds.isEmpty()) {
            for (Medication m : [
                SELECT Id, MedicationId__c
                FROM Medication
                WHERE MedicationId__c IN :medicationFhirIds
            ]) {
                if (m.MedicationId__c != null) {
                    medicationMap.put(m.MedicationId__c, m.Id);
                }
            }
        }

        Map<String, Id> organizationMap = new Map<String, Id>();
        if (!organizationFhirIds.isEmpty()) {
            for (HealthcareFacility hp : [
                SELECT Id, OrganizationId__c
                FROM HealthcareFacility
                WHERE OrganizationId__c IN :organizationFhirIds
            ]) {
                if (hp.OrganizationId__c != null) {
                    organizationMap.put(hp.OrganizationId__c, hp.Id);
                }
            }
        }

        /* -------------------------
           Deduplicate against existing records
        -------------------------- */
        Set<String> incomingRequestIds = new Set<String>();
        for (Map<String, Object> res : requestResources) {
            if (res.containsKey('id') && res.get('id') != null) {
                incomingRequestIds.add((String) res.get('id'));
            }
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

        /* -------------------------
           Build MedicationRequest records
        -------------------------- */
        List<MedicationRequest> requestsToInsert = new List<MedicationRequest>();

        for (Map<String, Object> res : requestResources) {
            String requestId = (String) res.get('id');

          if (existingRequestIds.contains(requestId) ||
    deletedRequestIds.contains(requestId)) continue;

            MedicationRequest mr = parseSingleMedicationRequest(res, patientMap, medicationMap, organizationMap);
            if (mr != null) requestsToInsert.add(mr);
        }

        if (!requestsToInsert.isEmpty()) {
            Database.insert(requestsToInsert,false);
            System.debug('✅ Inserted MedicationRequests: ' + requestsToInsert.size());
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

    /* FHIR ID */
    if (resource.containsKey('id') && resource.get('id') != null) {
        mr.MedicationRequestId__c = (String) resource.get('id');
    }

    /* Status */
    if (resource.containsKey('status')) {
        mr.Status = (String) resource.get('status');
    }
    
    mr.Type ='Order';

    /* Patient */
    Object subjectRaw = resource.get('subject');
    if (subjectRaw instanceof Map<String, Object>) {
        String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
        if (!String.isBlank(ref) && ref.contains('/')) {
            mr.PatientId = patientMap.get(ref.split('/')[1]);
        }
    }

    /* Medication */
    Object medRefRaw = resource.get('medicationReference');
    if (medRefRaw instanceof Map<String, Object>) {
        String ref = (String) ((Map<String, Object>) medRefRaw).get('reference');
        if (!String.isBlank(ref) && ref.contains('/')) {
            mr.MedicationId = medicationMap.get(ref.split('/')[1]);
        }
    }

    /* Requester display → Requester_Name__c */
    Object requesterRaw = resource.get('requester');
    if (requesterRaw instanceof Map<String, Object>) {
        String display = (String) ((Map<String, Object>) requesterRaw).get('display');
        if (!String.isBlank(display)) {
            mr.Requester_Name__c = display;
        }
    }

    /* Performer Organization → PerformerId via HealthcareProvider */
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