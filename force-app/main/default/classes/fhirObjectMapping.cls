public without sharing class fhirObjectMapping {
public static void parseAndInsertEncounters(String rawJson) {
    if (String.isBlank(rawJson)) return;

    try {
        Object deserialized = JSON.deserializeUntyped(rawJson);
        if (!(deserialized instanceof Map<String, Object>)) return;

        Map<String, Object> jsonData = (Map<String, Object>) deserialized;
        if (jsonData.isEmpty()) return;

        List<Map<String, Object>> encounterResources = new List<Map<String, Object>>();
        Set<String> patientFhirIds = new Set<String>();
        Set<String> locationFhirIds = new Set<String>();
        Set<String> conditionFhirIds = new Set<String>();
        Set<String> practitionerFhirIds = new Set<String>();

        /* -------------------------
           Collect Encounters
        -------------------------- */
        String resourceType = (String) jsonData.get('resourceType');
        if ('Bundle'.equals(resourceType)) {
            Object entriesRaw = jsonData.get('entry');
            if (!(entriesRaw instanceof List<Object>)) return;
            List<Object> entries = (List<Object>) entriesRaw;

            for (Object o : entries) {
                if (!(o instanceof Map<String, Object>)) continue;

                Map<String, Object> entryMap = (Map<String, Object>) o;
                Object resRaw = entryMap.get('resource');
                if (!(resRaw instanceof Map<String, Object>)) continue;

                Map<String, Object> res = (Map<String, Object>) resRaw;
                if (!'Encounter'.equals((String) res.get('resourceType'))) continue;

                encounterResources.add(res);

                Object subjectRaw = res.get('subject');
                if (subjectRaw instanceof Map<String, Object>) {
                    String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
                    if (!String.isBlank(ref) && ref.contains('/')) {
                        patientFhirIds.add(ref.split('/')[1]);
                    }
                }

                // Collect LocationIds for bulk query
                Object locationRaw = res.get('location');
                if (locationRaw instanceof List<Object>) {
                    for (Object locObj : (List<Object>) locationRaw) {
                        if (locObj instanceof Map<String, Object>) {
                            Map<String, Object> locWrapper = (Map<String, Object>) locObj;
                            Object locRefRaw = locWrapper.get('location');
                            if (locRefRaw instanceof Map<String, Object>) {
                                String ref = (String) ((Map<String, Object>) locRefRaw).get('reference');
                                if (!String.isBlank(ref) && ref.contains('/')) {
                                    locationFhirIds.add(ref.split('/')[1]);
                                }
                            }
                        }
                    }
                }

                // Collect ConditionIds
                Object diagnosisRaw = res.get('diagnosis');
                if (diagnosisRaw instanceof List<Object>) {
                    for (Object d : (List<Object>) diagnosisRaw) {
                        if (d instanceof Map<String, Object>) {
                            Map<String, Object> diag = (Map<String, Object>) d;
                            Object condRaw = diag.get('condition');
                            if (condRaw instanceof Map<String, Object>) {
                                String condRef = (String) ((Map<String, Object>) condRaw).get('reference');
                                if (!String.isBlank(condRef) && condRef.contains('/')) {
                                    conditionFhirIds.add(condRef.split('/')[1]);
                                }
                            }
                        }
                    }
                }

                // Collect PractitionerIds
                Object participantRaw = res.get('participant');
                if (participantRaw instanceof List<Object>) {
                    for (Object partObj : (List<Object>) participantRaw) {
                        if (partObj instanceof Map<String, Object>) {
                            Map<String, Object> part = (Map<String, Object>) partObj;
                            Object indivRaw = part.get('individual');
                            if (indivRaw instanceof Map<String, Object>) {
                                String pracRef = (String) ((Map<String, Object>) indivRaw).get('reference');
                                if (!String.isBlank(pracRef) && pracRef.contains('/')) {
                                    practitionerFhirIds.add(pracRef.split('/')[1]);
                                }
                            }
                        }
                    }
                }
            }
        } else if ('Encounter'.equals(resourceType)) {
            encounterResources.add(jsonData);
            Object subjectRaw = jsonData.get('subject');
            if (subjectRaw instanceof Map<String, Object>) {
                String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
                if (!String.isBlank(ref) && ref.contains('/')) {
                    patientFhirIds.add(ref.split('/')[1]);
                }
            }
        }

        if (encounterResources.isEmpty()) return;

        /* -------------------------
           Fetch existing mappings in bulk
        -------------------------- */
        Map<String, Id> patientToContactMap = new Map<String, Id>();
        if (!patientFhirIds.isEmpty()) {
            for (Account a : [
                SELECT Id, Metriport_Patient_Id__c, PersonContactId
                FROM Account
                WHERE IsPersonAccount = true
                  AND Metriport_Patient_Id__c IN :patientFhirIds
            ]) {
                if (a.PersonContactId != null && a.Metriport_Patient_Id__c != null) {
                    patientToContactMap.put(a.Metriport_Patient_Id__c, a.Id);
                }
            }
        }

        Map<String, Id> locationMap = new Map<String, Id>();
        if (!locationFhirIds.isEmpty()) {
            for (SObject l : [
                SELECT Id, LocationId__c
                FROM Location
                WHERE LocationId__c IN :locationFhirIds
            ]) {
                locationMap.put((String)l.get('LocationId__c'), l.Id);
            }
        }

        Map<String, Id> conditionMap = new Map<String, Id>();
        if (!conditionFhirIds.isEmpty()) {
            for (HealthCondition hc : [
                SELECT Id, ConditionId__c
                FROM HealthCondition
                WHERE ConditionId__c IN :conditionFhirIds
            ]) {
                conditionMap.put(hc.ConditionId__c, hc.Id);
            }
        }

        Map<String, Id> practitionerMap = new Map<String, Id>();
        if (!practitionerFhirIds.isEmpty()) {
            for (HealthcarePractitionerFacility hp : [
                SELECT Id, PractitionerId__c
                FROM HealthcarePractitionerFacility
                WHERE PractitionerId__c IN :practitionerFhirIds
            ]) {
                practitionerMap.put(hp.PractitionerId__c, hp.Id);
            }
        }

        /* -------------------------
           Skip duplicates (FHIR Id)
        -------------------------- */
        Set<String> visitFhirIds = new Set<String>();
        for (Map<String, Object> res : encounterResources) {
            if (res.containsKey('id') && res.get('id') != null) {
                visitFhirIds.add((String) res.get('id'));
            }
        }

        Set<String> existingVisitIds = new Set<String>();
        if (!visitFhirIds.isEmpty()) {
            for (Visit v : [
                SELECT VisitId__c
                FROM Visit
                WHERE VisitId__c IN :visitFhirIds
            ]) {
                existingVisitIds.add(v.VisitId__c);
            }
        }
        Set<String> deletedVisitIds = new Set<String>();

        if (!visitFhirIds.isEmpty()) {
            for (Deleted_Record_Audit__c del : [
                SELECT External_Id_Metriport__c
                FROM Deleted_Record_Audit__c
                WHERE External_Id_Metriport__c IN :visitFhirIds
                AND Object_API_Name__c = 'Visit'
            ]) {
                deletedVisitIds.add(del.External_Id_Metriport__c);
            }
        }

        /* -------------------------
           Dedup key: Visit_Name__c + PlaceId + PlannedVisitStartTime
           Fetch existing composite keys from Visit
        -------------------------- */
        Set<Id> patientAccountIds = new Set<Id>(patientToContactMap.values());
        Set<String> existingVisitDedupeKeys = new Set<String>();
        if (!patientAccountIds.isEmpty()) {
            for (Visit v : [
                SELECT Visit_Name__c, PlaceId, PlannedVisitStartTime
                FROM Visit
                WHERE AccountId IN :patientAccountIds
            ]) {
                String key = buildVisitDedupeKey(v.Visit_Name__c, v.PlaceId, v.PlannedVisitStartTime);
                if (!String.isBlank(key)) existingVisitDedupeKeys.add(key);
            }
        }

        /* -------------------------
           Create Visit records
        -------------------------- */
        List<Visit> toInsert = new List<Visit>();
        Set<String> inFlightDedupeKeys = new Set<String>();

        for (Map<String, Object> res : encounterResources) {
            String visitId = (String) res.get('id');
            if (existingVisitIds.contains(visitId) ||
                deletedVisitIds.contains(visitId)) {
                System.debug('Skipping Visit (Duplicate/Deleted): ' + visitId);
                continue;
            }
            Visit v = parseSingleEncounter(res, patientToContactMap, locationMap, conditionMap, practitionerMap);
            if (v == null) continue;

            // Dedup by composite key: Visit_Name__c + PlaceId + PlannedVisitStartTime
            String dedupeKey = buildVisitDedupeKey(v.Visit_Name__c, v.PlaceId, v.PlannedVisitStartTime);
            if (!String.isBlank(dedupeKey)) {
                if (existingVisitDedupeKeys.contains(dedupeKey) || inFlightDedupeKeys.contains(dedupeKey)) {
                    System.debug('Skipping Visit (Composite Duplicate): ' + dedupeKey);
                    continue;
                }
                inFlightDedupeKeys.add(dedupeKey);
            }

            // Skip "No Data Available" visit names
            if (!String.isBlank(v.Visit_Name__c) && v.Visit_Name__c.trim().equalsIgnoreCase('No Data Available')) {
                System.debug('⏭️ Skipping Visit (No Data Available name): ' + v.VisitId__c);
                continue;
            }

            toInsert.add(v);
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
    
                Visit failedVisit = toInsert[i];
    
                errorLogs.add(new Error_Log__c(
                    Object_API_Name__c    = 'Visit',
                    Error_Message__c      = String.join(errorMessages, '\n'),
                    Record_External_Id__c = failedVisit.VisitId__c,
                    Context__c            = 'parseAndInsertEncounters',
                    Stack_Trace__c        = 'AccountId: ' + failedVisit.AccountId +
                                            ' | VisitId: ' + failedVisit.VisitId__c
                ));
            }
    }

    if (!errorLogs.isEmpty()) {
        Database.insert(errorLogs, false);
        System.debug('⚠️ Failed Visit inserts logged: ' + errorLogs.size());
    }

    System.debug('✅ Inserted Visit records: ' + successCount +
                 ' | Failed: ' + (toInsert.size() - successCount));
}

    } catch (Exception e) {
        System.debug('❌ Error parsing Encounter: ' + e.getMessage());
    }
}

/* -------------------------
   Helper: build Organization dedupe key
-------------------------- */
private static String buildOrgDedupeKey(String name) {
    String namePart = String.isBlank(name) ? '' : name.trim().toLowerCase();
    if (String.isBlank(namePart)) return null;
    return namePart;
}

/* -------------------------
   Helper: build Visit dedupe key
-------------------------- */
private static String buildVisitDedupeKey(String visitName, Id placeId, Datetime startTime) {
    String namePart  = String.isBlank(visitName) ? '' : visitName.trim().toLowerCase();
    String placePart = (placeId != null) ? String.valueOf(placeId) : '';
    String timePart  = (startTime != null) ? String.valueOf(startTime) : '';
    if (String.isBlank(namePart) && String.isBlank(placePart) && String.isBlank(timePart)) return null;
    return namePart + '|' + placePart + '|' + timePart;
}

/* -------------------------
   Updated parseSingleEncounter to use bulk maps
-------------------------- */
private static Visit parseSingleEncounter(
    Map<String, Object> resource,
    Map<String, Id> patientToContactMap,
    Map<String, Id> locationMap,
    Map<String, Id> conditionMap,
    Map<String, Id> practitionerMap
) {
    if (resource == null) return null;

    Visit v = new Visit();

    /* Encounter FHIR Id */
    if (resource.containsKey('id') && resource.get('id') != null) {
        v.VisitId__c = (String) resource.get('id');
    }

    /* PlaceId from first location */
    v.PlaceId = null;
    Object locationRaw = resource.get('location');
    if (locationRaw instanceof List<Object> && !((List<Object>) locationRaw).isEmpty()) {
        Object firstLocationRaw = ((List<Object>) locationRaw)[0];
        if (firstLocationRaw instanceof Map<String, Object>) {
            Map<String, Object> locWrapper = (Map<String, Object>) firstLocationRaw;
            Object locRefRaw = locWrapper.get('location');
            if (locRefRaw instanceof Map<String, Object>) {
                String ref = (String) ((Map<String, Object>) locRefRaw).get('reference');
                if (!String.isBlank(ref) && ref.contains('/')) {
                    String fhirLocationId = ref.split('/')[1];
                    if (locationMap.containsKey(fhirLocationId)) {
                        v.PlaceId = locationMap.get(fhirLocationId);
                    }
                }
            }
        }
    }

    /* Visit Name */
    Object typeRaw = resource.get('type');
    if (typeRaw instanceof List<Object> && !((List<Object>) typeRaw).isEmpty()) {
        Object firstTypeRaw = ((List<Object>) typeRaw)[0];
        if (firstTypeRaw instanceof Map<String, Object>) {
            String typeText = (String) ((Map<String, Object>) firstTypeRaw).get('text');
            if (!String.isBlank(typeText)) v.Visit_Name__c = typeText;
        }
    }

    /* Reason */
    Object reasonRaw = resource.get('reasonCode');
    if (reasonRaw instanceof List<Object> && !((List<Object>) reasonRaw).isEmpty()) {
        Object firstReasonRaw = ((List<Object>) reasonRaw)[0];
        if (firstReasonRaw instanceof Map<String, Object>) {
            String reasonText = (String) ((Map<String, Object>) firstReasonRaw).get('text');
            if (!String.isBlank(reasonText)) v.Reason__c = reasonText;
        }
    }

    /* Period Start / End */
    Object periodRaw = resource.get('period');
    if (periodRaw instanceof Map<String, Object>) {
        Map<String, Object> period = (Map<String, Object>) periodRaw;

        try {
            if (period.containsKey('start') && period.get('start') != null) {
                v.PlannedVisitStartTime = Datetime.valueOfGmt(
                    String.valueOf(period.get('start')).replace('T', ' ').replace('Z', '')
                );
            }
        } catch (Exception ex) {
            System.debug('⚠️ Could not parse encounter start: ' + period.get('start'));
        }

        try {
            if (period.containsKey('end') && period.get('end') != null) {
                v.PlannedVisitEndTime = Datetime.valueOfGmt(
                    String.valueOf(period.get('end')).replace('T', ' ').replace('Z', '')
                );
            }
        } catch (Exception ex) {
            System.debug('⚠️ Could not parse encounter end: ' + period.get('end'));
        }
    }

    /* Patient → Contact */
    Object subjectRaw = resource.get('subject');
    if (subjectRaw instanceof Map<String, Object>) {
        String ref = (String) ((Map<String, Object>) subjectRaw).get('reference');
        if (!String.isBlank(ref) && ref.contains('/')) {
            v.AccountId = patientToContactMap.get(ref.split('/')[1]);
        }
    }

    /* Encounter Class */
    Object classRaw = resource.get('class');
    if (classRaw instanceof Map<String, Object>) {
        String classDisplay = (String)((Map<String, Object>)classRaw).get('display');
        if (!String.isBlank(classDisplay)) v.Class__c = classDisplay;
    }

    /* Service Type */
    Object serviceTypeRaw = resource.get('serviceType');
    if (serviceTypeRaw instanceof Map<String, Object>) {
        String serviceText = (String)((Map<String, Object>)serviceTypeRaw).get('text');
        if (!String.isBlank(serviceText)) v.Service_Type__c = serviceText;
    }

    /* Encounter Status */
    if (resource.containsKey('status')) {
        v.Current_Status__c = (String) resource.get('status');
    }

    /* Medical Condition */
    Object diagnosisRaw = resource.get('diagnosis');
    if (diagnosisRaw instanceof List<Object> && !((List<Object>)diagnosisRaw).isEmpty()) {
        Map<String, Object> diag = (Map<String, Object>) ((List<Object>)diagnosisRaw)[0];
        Object condRaw = diag.get('condition');

        if (condRaw instanceof Map<String, Object>) {
            String condRef = (String)((Map<String, Object>)condRaw).get('reference');
            if (!String.isBlank(condRef) && condRef.contains('/')) {
                String conditionId = condRef.split('/')[1];
                if (conditionMap.containsKey(conditionId)) {
                    v.Health_Condition__c = conditionMap.get(conditionId);
                }
            }
        }
    }

    /* Practitioner */
    Object participantRaw = resource.get('participant');
    if (participantRaw instanceof List<Object> && !((List<Object>)participantRaw).isEmpty()) {
        Map<String, Object> part = (Map<String, Object>) ((List<Object>)participantRaw)[0];
        Object indivRaw = part.get('individual');

        if (indivRaw instanceof Map<String, Object>) {
            String pracRef = (String)((Map<String, Object>)indivRaw).get('reference');
            if (!String.isBlank(pracRef) && pracRef.contains('/')) {
                String practitionerId = pracRef.split('/')[1];
                if (practitionerMap.containsKey(practitionerId)) {
                    v.Practitioner__c = practitionerMap.get(practitionerId);
                }
            }
        }
    }

    /* Transfer Location (second location) */
    if (locationRaw instanceof List<Object> && ((List<Object>)locationRaw).size() > 1) {
        Map<String, Object> secondLoc = (Map<String, Object>) ((List<Object>)locationRaw)[1];
        Object locRefRaw = secondLoc.get('location');

        if (locRefRaw instanceof Map<String, Object>) {
            String ref = (String)((Map<String, Object>)locRefRaw).get('reference');
            if (!String.isBlank(ref) && ref.contains('/')) {
                String fhirLocationId = ref.split('/')[1];
                if (locationMap.containsKey(fhirLocationId)) {
                    v.Transfer_Location__c = locationMap.get(fhirLocationId);
                }
            }
        }
    }

    return v;
}



    
    //-----------------------------Organization------------------------------

        public static void parseAndInsertOrganizations(String rawJson) {
            if (String.isBlank(rawJson)) return;
        
            try {
                Map<String, Object> jsonData =
                    (Map<String, Object>) JSON.deserializeUntyped(rawJson);
        
                List<Map<String, Object>> orgResources = new List<Map<String, Object>>();
                Set<String> patientIds = new Set<String>();
        
                /* -------------------------
                   Collect Organizations & Patient IDs (ONLY from Bundle)
                -------------------------- */
                if ('Bundle'.equals(jsonData.get('resourceType'))) {
                    List<Object> entries = (List<Object>) jsonData.get('entry');
                    if (entries != null) {
                        for (Object o : entries) {
                            Map<String, Object> res =
                                (Map<String, Object>) ((Map<String, Object>) o).get('resource');
                            if (res == null) continue;
        
                            if ('Organization'.equals(res.get('resourceType'))) {
                                orgResources.add(res);
                            }
        
                            if ('Patient'.equals(res.get('resourceType'))) {
                                String pid = (String) res.get('id');
                                if (!String.isBlank(pid)) {
                                    patientIds.add(pid);
                                }
                            }
                        }
                    }
                } else if ('Organization'.equals(jsonData.get('resourceType'))) {
                    orgResources.add(jsonData);
                }
        
                if (orgResources.isEmpty() || patientIds.isEmpty()) return;
        
                /* -------------------------
                   Fetch Accounts by Metriport Patient Id
                -------------------------- */
                Map<String, Id> patientAccountMap = new Map<String, Id>();
        
                for (Account a : [
                    SELECT Id, Metriport_Patient_Id__c
                    FROM Account
                    WHERE Metriport_Patient_Id__c IN :patientIds
                ]) {
                    patientAccountMap.put(a.Metriport_Patient_Id__c, a.Id);
                }
        
                if (patientAccountMap.isEmpty()) return;
        
                /* -------------------------
                   Prevent duplicate HealthCareFacility
                -------------------------- */
                Set<String> orgIds = new Set<String>();
                for (Map<String, Object> res : orgResources) {
                    String orgId = (String) res.get('id');
                    if (!String.isBlank(orgId)) orgIds.add(orgId);
                }
        
                Map<String, HealthCareFacility> existingHFs = new Map<String, HealthCareFacility>();
                for (HealthCareFacility hf : [
                    SELECT Id, OrganizationId__c
                    FROM HealthCareFacility
                    WHERE OrganizationId__c IN :orgIds
                ]) {
                    existingHFs.put(hf.OrganizationId__c, hf);
                }
                
                Set<String> deletedOrgIds = new Set<String>();

                if (!orgIds.isEmpty()) {
                    for (Deleted_Record_Audit__c del : [
                        SELECT External_Id_Metriport__c
                        FROM Deleted_Record_Audit__c
                        WHERE External_Id_Metriport__c IN :orgIds
                        AND Object_API_Name__c = 'HealthCareFacility'
                    ]) {
                        deletedOrgIds.add(del.External_Id_Metriport__c);
                    }
                }
        
                /* -------------------------
                   Prepare HealthCareFacility records
                   → Use ANY PatientId from Bundle
                -------------------------- */
                // pick one PatientId (Bundle-level)
                String bundlePatientId = patientIds.iterator().next();
                Id accountId = patientAccountMap.get(bundlePatientId);
        
                if (accountId == null) return;

                // Dedup key: Name — scoped to this patient's account
                Set<String> existingOrgDedupeKeys = new Set<String>();
                for (HealthCareFacility hf : [
                    SELECT Name
                    FROM HealthCareFacility
                    WHERE Name != null
                      AND AccountId = :accountId
                ]) {
                    String key = buildOrgDedupeKey(hf.Name);
                    if (!String.isBlank(key)) existingOrgDedupeKeys.add(key);
                }

                List<HealthCareFacility> hfToInsert = new List<HealthCareFacility>();
                Set<String> inFlightOrgDedupeKeys = new Set<String>();
        
                for (Map<String, Object> res : orgResources) {
                    String orgId = (String) res.get('id');
                   if (existingHFs.containsKey(orgId) || deletedOrgIds.contains(orgId)) {
                        System.debug('⏭️ Skipping Organization (Duplicate/Deleted): ' + orgId);
                        continue;
                    }
        
                    HealthCareFacility hf = new HealthCareFacility();
                    hf.AccountId = accountId; // ✅ SAME Account for all Orgs
                    hf.OrganizationId__c = orgId;
        
                    /* Active */
                    if (res.containsKey('active'))
                        hf.Active__c = (Boolean) res.get('active');
        
                    /* Name */
                    hf.Name = (String) res.get('name');
        
                    /* Address */
                    if (res.containsKey('address')) {
                        List<Object> addresses = (List<Object>) res.get('address');
                        if (!addresses.isEmpty()) {
                            Map<String, Object> addr =
                                (Map<String, Object>) addresses[0];
        
                            List<String> streetLines = new List<String>();
                            if (addr.containsKey('line')) {
                                for (Object l : (List<Object>) addr.get('line')) {
                                    if (l != null) streetLines.add(String.valueOf(l));
                                }
                            }
        
                            hf.Mailing_Address__Street__s =
                                streetLines.isEmpty() ? null : String.join(streetLines, ', ');
                            hf.Mailing_Address__City__s = (String) addr.get('city');
                            String rawState = (String) addr.get('state');
                            hf.Mailing_Address__StateCode__s = StateNormalizer.normalize(rawState);
                            hf.Mailing_Address__CountryCode__s = 'US';
                            hf.Mailing_Address__PostalCode__s = (String) addr.get('postalCode');
                        }
                    }
        
                    /* Telecom */
                    if (res.containsKey('telecom')) {
                        for (Object t : (List<Object>) res.get('telecom')) {
                            if (!(t instanceof Map<String, Object>)) continue;
                            Map<String, Object> telecom = (Map<String, Object>) t;
        
                            String systemtd = (String) telecom.get('system');
                            String value = (String) telecom.get('value');
                            if (String.isBlank(value)) continue;
        
                            if ('phone'.equals(systemtd)) hf.Phone__c = value;
                            else if ('email'.equals(systemtd)) hf.Email__c = value;
                        }
                    }
        
                    /* Contact */
                    if (res.containsKey('contact')) {
                        List<Object> contacts = (List<Object>) res.get('contact');
                        if (!contacts.isEmpty()) {
                            Map<String, Object> contactObj =
                                (Map<String, Object>) contacts[0];
        
                            if (contactObj.containsKey('name')) {
                                Map<String, Object> nameObj =
                                    (Map<String, Object>) contactObj.get('name');
                                hf.Contact_Person__c = (String) nameObj.get('text');
                            }
        
                            if (contactObj.containsKey('telecom')) {
                                List<Object> ct = (List<Object>) contactObj.get('telecom');
                                if (!ct.isEmpty()) {
                                    hf.Contact_Person_Phone__c =
                                        (String) ((Map<String, Object>) ct[0]).get('value');
                                }
                            }
                        }
                    }
        
                    // Skip if no address
                    if (!res.containsKey('address') || ((List<Object>) res.get('address')).isEmpty()) {
                        System.debug('⏭️ Skipping Organization (no address): ' + orgId);
                        continue;
                    }

                    // Dedup by composite key: Name
                    String orgDedupeKey = buildOrgDedupeKey(hf.Name);
                    if (!String.isBlank(orgDedupeKey)) {
                        if (existingOrgDedupeKeys.contains(orgDedupeKey) || inFlightOrgDedupeKeys.contains(orgDedupeKey)) {
                            System.debug('⏭️ Skipping Organization (Composite Duplicate): ' + orgDedupeKey);
                            continue;
                        }
                        inFlightOrgDedupeKeys.add(orgDedupeKey);
                    }

                    hfToInsert.add(hf);
                }
        
                /* -------------------------
                   Insert HealthCareFacility
                -------------------------- */
               if (!hfToInsert.isEmpty()) {
                        Database.SaveResult[] results = Database.insert(hfToInsert, false);
                        
                        List<Error_Log__c> errorLogs = new List<Error_Log__c>();
                        Integer successCount = 0;
                    
                        for (Integer i = 0; i < results.size(); i++) {
                            Database.SaveResult sr = results[i];
                            
                            if (sr.isSuccess()) {
                                successCount++;
                            } else {
                                List<String> errorMessages = new List<String>();
                                for (Database.Error err : sr.getErrors()) {
                                    errorMessages.add(
                                        'Status: ' + err.getStatusCode() + 
                                        ' | Message: ' + err.getMessage() + 
                                        ' | Fields: ' + String.join(err.getFields(), ', ')
                                    );
                                }
                    
                                HealthCareFacility failedHF = hfToInsert[i];
                    
                                errorLogs.add(new Error_Log__c(
                                    Object_API_Name__c    = 'HealthCareFacility',
                                    Error_Message__c      = String.join(errorMessages, '\n'),
                                    Record_External_Id__c = failedHF.OrganizationId__c,
                                    Context__c            = 'parseAndInsertOrganizations',
                                    Stack_Trace__c        = 'AccountId: ' + failedHF.AccountId + 
                                                            ' | OrgId: ' + failedHF.OrganizationId__c
                                ));
                            }
                        }
                    
                        if (!errorLogs.isEmpty()) {
                            Database.insert(errorLogs, false);
                            System.debug('⚠️ Failed HealthCareFacility inserts logged: ' + errorLogs.size());
                        }
                    
                        System.debug('✅ Inserted HealthCareFacility records: ' + successCount + 
                                     ' | Failed: ' + (hfToInsert.size() - successCount));
                    }
        
            } catch (Exception e) {
                System.debug('❌ Error parsing Organization: ' + e.getMessage());
            }
        }



    //------------------------Location------------------------------
  
         public static void parseAndInsertLocations(String rawJson) {
        if (String.isBlank(rawJson)) return;
    
        try {
            Map<String, Object> jsonData =
                (Map<String, Object>) JSON.deserializeUntyped(rawJson);
    
            List<Map<String, Object>> locationResources =
                new List<Map<String, Object>>();
    
            if ('Bundle'.equals(jsonData.get('resourceType'))) {
    
                List<Object> entries =
                    (List<Object>) jsonData.get('entry');
                if (entries == null) return;
    
                for (Object o : entries) {
                    Map<String, Object> res =
                        (Map<String, Object>) ((Map<String, Object>) o)
                            .get('resource');
    
                    if (res != null &&
                        res.get('resourceType') == 'Location') {
                        locationResources.add(res);
                    }
                }
    
            } else if ('Location'.equals(jsonData.get('resourceType'))) {
                locationResources.add(jsonData);
            }
    
            if (locationResources.isEmpty()) return;
    
                Set<String> incomingLocationIds = new Set<String>();
                for (Map<String, Object> res : locationResources) {
                    if (res.get('id') != null) {
                        incomingLocationIds.add((String) res.get('id'));
                    }
                }
                
            
                Set<String> existingLocationIds = new Set<String>();
        
        if (!incomingLocationIds.isEmpty()) {
        
            String soql =
                'SELECT LocationId__c FROM Location ' +
                'WHERE LocationId__c IN :incomingLocationIds';
        
            for (SObject s : Database.query(soql)) {
                existingLocationIds.add(
                    (String) s.get('LocationId__c')
                );
            }
        }
            Set<String> deletedLocationIds = new Set<String>();

            if (!incomingLocationIds.isEmpty()) {
                for (Deleted_Record_Audit__c del : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE External_Id_Metriport__c IN :incomingLocationIds
                    AND Object_API_Name__c = 'Location'
                ]) {
                    deletedLocationIds.add(del.External_Id_Metriport__c);
                }
            }


            
            List<SObject> toInsert = new List<SObject>();
    
           for (Map<String, Object> res : locationResources) {
            String locationId = (String) res.get('id');
           if (existingLocationIds.contains(locationId) || deletedLocationIds.contains(locationId)) {
            System.debug('⏭️ Skipping Location (Duplicate/Deleted): ' + locationId);
            continue;
        }
        
            SObject loc = parseSingleLocation(res);
            if (loc != null) {
                toInsert.add(loc); 
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

                        SObject failedLoc = toInsert[i];

                        errorLogs.add(new Error_Log__c(
                            Object_API_Name__c    = 'Location',
                            Error_Message__c      = String.join(errorMessages, '\n'),
                            Record_External_Id__c = (String) failedLoc.get('LocationId__c'),
                            Context__c            = 'parseAndInsertLocations',
                            Stack_Trace__c        = 'LocationId: ' + (String) failedLoc.get('LocationId__c')
                        ));
                    }
                }

                if (!errorLogs.isEmpty()) {
                    Database.insert(errorLogs, false);
                    System.debug('⚠️ Failed Location inserts logged: ' + errorLogs.size());
                }

                System.debug('✅ Inserted Location records: ' + successCount +
                             ' | Failed: ' + (toInsert.size() - successCount));
            }
    
        } catch (Exception e) {
            System.debug(
                '❌ Error parsing Location: ' +
                e.getMessage()
            );
        }
    }

            private static SObject parseSingleLocation(
    Map<String, Object> resource
) {
    Schema.SObjectType locType =
        Schema.getGlobalDescribe().get('Location');

    if (locType == null) {
        System.debug('❌ Location SObjectType not found');
        return null;
    }

    SObject loc = locType.newSObject();

    // FHIR Id
    loc.put('LocationId__c', (String) resource.get('id'));

    // Name
    loc.put('Name', (String) resource.get('name'));

    // Picklist (NOT record type)
    loc.put('LocationType', 'Facility');

    // Address
    Map<String, Object> addr =
        (Map<String, Object>) resource.get('address');

    if (addr != null) {

        if (addr.containsKey('line')) {
            List<Object> lines =
                (List<Object>) addr.get('line');

            List<String> streetLines = new List<String>();
            for (Object l : lines) {
                if (l != null) {
                    streetLines.add(String.valueOf(l));
                }
            }

            if (!streetLines.isEmpty()) {
                loc.put(
                    'Location_Address__Street__s',
                    String.join(streetLines, ', ')
                );
            }
        }

        loc.put('Location_Address__City__s', addr.get('city'));
        String rawState = (String) addr.get('state');
        loc.put('Location_Address__StateCode__s', StateNormalizer.normalize(rawState));
        loc.put('Location_Address__PostalCode__s', addr.get('postalCode'));
        String countrycode = 'US';
        loc.put('Location_Address__CountryCode__s', countrycode);
    }

    return loc;
}
    
    //---------------------Practitioner-------------------
   
        public static void parseAndInsertPractitioners(String rawJson) {
        if (String.isBlank(rawJson)) return;
    
        try {
            Map<String, Object> jsonData =
                (Map<String, Object>) JSON.deserializeUntyped(rawJson);
    
            List<Map<String, Object>> practitionerResources = new List<Map<String, Object>>();
    
            /* -------------------------
               Collect Practitioners
            -------------------------- */
            if ('Bundle'.equals(jsonData.get('resourceType'))) {
                List<Object> entries = (List<Object>) jsonData.get('entry');
                if (entries != null) {
                    for (Object o : entries) {
                        Map<String, Object> res =
                            (Map<String, Object>) ((Map<String, Object>) o).get('resource');
    
                        if (res != null && 'Practitioner'.equals(res.get('resourceType'))) {
                            practitionerResources.add(res);
                        }
                    }
                }
            } else if ('Practitioner'.equals(jsonData.get('resourceType'))) {
                practitionerResources.add(jsonData);
            }
    
            if (practitionerResources.isEmpty()) return;
            //Patient 
            Set<String> patientIds = new Set<String>();
            
                if ('Bundle'.equals(jsonData.get('resourceType'))) {
        List<Object> entries = (List<Object>) jsonData.get('entry');
        if (entries != null) {
            for (Object o : entries) {
                Map<String, Object> res =
                    (Map<String, Object>) ((Map<String, Object>) o).get('resource');
    
                if (res == null) continue;
    
                String rt = (String) res.get('resourceType');
    
                if ('Patient'.equals(rt)) {
                    String pid = (String) res.get('id');
                    if (pid != null) {
                        patientIds.add(pid);
                    }
                }
    
                if ('Practitioner'.equals(rt)) {
                    practitionerResources.add(res);
                }
            }
        }
    } else if ('Practitioner'.equals(jsonData.get('resourceType'))) {
        practitionerResources.add(jsonData);
    }
            Map<String, Id> patientAccountMap = new Map<String, Id>();

if (!patientIds.isEmpty()) {
    for (Account a : [
        SELECT Id, Metriport_Patient_Id__c
        FROM Account
        WHERE Metriport_Patient_Id__c IN :patientIds
    ]) {
        patientAccountMap.put(a.Metriport_Patient_Id__c, a.Id);
    }
}



    
            /* -------------------------
               Collect Incoming Practitioner IDs
            -------------------------- */
            Set<String> incomingPractitionerIds = new Set<String>();
            for (Map<String, Object> res : practitionerResources) {
                if (res.get('id') != null) {
                    incomingPractitionerIds.add((String) res.get('id'));
                }
            }
    
            /* -------------------------
               Existing Practitioner Lookup
            -------------------------- */
            Set<String> existingPractitionerIds = new Set<String>();
            if (!incomingPractitionerIds.isEmpty()) {
                for (HealthcarePractitionerFacility hp : [
                    SELECT PractitionerId__c
                    FROM HealthcarePractitionerFacility
                    WHERE PractitionerId__c IN :incomingPractitionerIds
                ]) {
                    existingPractitionerIds.add(hp.PractitionerId__c);
                }
            }
            
            Set<String> deletedPractitionerIds = new Set<String>();
            if (!incomingPractitionerIds.isEmpty()) {
                for (Deleted_Record_Audit__c del : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE Object_API_Name__c = 'HealthcarePractitionerFacility'
                    AND External_Id_Metriport__c IN :incomingPractitionerIds
                ]) {
                    deletedPractitionerIds.add(del.External_Id_Metriport__c);
                }
            }

            /* -------------------------
               Dedup key: Name + Phone__c
               Fetch existing composite keys from HealthcarePractitionerFacility
            -------------------------- */
            Set<Id> practPatientAccountIds = new Set<Id>(patientAccountMap.values());
            Set<String> existingPractitionerDedupeKeys = new Set<String>();
            if (!practPatientAccountIds.isEmpty()) {
                for (HealthcarePractitionerFacility hp : [
                    SELECT Name, Phone__c
                    FROM HealthcarePractitionerFacility
                    WHERE Name != null
                      AND AccountId IN :practPatientAccountIds
                ]) {
                    String key = buildPractitionerDedupeKey(hp.Name, hp.Phone__c);
                    if (!String.isBlank(key)) existingPractitionerDedupeKeys.add(key);
                }
            }
    
            /* -------------------------
               Build Practitioner Records
            -------------------------- */
            Set<String> processedPractitionerIds = new Set<String>();
            Set<String> inFlightPractitionerDedupeKeys = new Set<String>();
            List<HealthcarePractitionerFacility> toInsert =
                new List<HealthcarePractitionerFacility>();
    
            for (Map<String, Object> res : practitionerResources) {
                String practitionerId = (String) res.get('id');
    
                if (existingPractitionerIds.contains(practitionerId) || deletedPractitionerIds.contains(practitionerId)) {
                    System.debug('⏭️ Skipping Practitioner (Duplicate/Deleted): ' + practitionerId);
                    continue;
                }
                
              if (processedPractitionerIds.contains(practitionerId)) continue;

    
                HealthcarePractitionerFacility hp =
                    parseSinglePractitioner(res);
                if (hp != null && !String.isBlank(hp.Name) &&
                    hp.Name.trim().equalsIgnoreCase('No Data Available')) {
                    System.debug('⏭️ Skipping Practitioner (No Data Available name): ' + practitionerId);
                    continue;
                }
                
                if (!patientAccountMap.isEmpty()) {
        hp.AccountId =
            patientAccountMap.values().isEmpty()
                ? null
                : patientAccountMap.values()[0];
    }

    
                if (hp != null) {
                    // Skip if no phone AND no address
                    Boolean hasPhone   = !String.isBlank(hp.Phone__c);
                    Boolean hasAddress = !String.isBlank(hp.Address__Street__s)
                                     || !String.isBlank(hp.Address__City__s)
                                     || !String.isBlank(hp.Address__PostalCode__s);
                    if (!hasPhone && !hasAddress) {
                        System.debug('⏭️ Skipping Practitioner (no phone and no address): ' + practitionerId);
                        continue;
                    }

                    // Skip if no Speciality AND no Qualification
                    Boolean hasQualification = !String.isBlank(hp.Qualification__c);
                    Boolean hasSpeciality    = !String.isBlank(hp.Specialty__c);
                    if (!hasQualification && !hasSpeciality) {
                        System.debug('⏭️ Skipping Practitioner (no Speciality and no Qualification): ' + practitionerId);
                        continue;
                    }

                    // Dedup by composite key: Name + Phone__c
                    String dedupeKey = buildPractitionerDedupeKey(hp.Name, hp.Phone__c);
                    if (!String.isBlank(dedupeKey)) {
                        if (existingPractitionerDedupeKeys.contains(dedupeKey) || inFlightPractitionerDedupeKeys.contains(dedupeKey)) {
                            System.debug('⏭️ Skipping Practitioner (Composite Duplicate): ' + dedupeKey);
                            continue;
                        }
                        inFlightPractitionerDedupeKeys.add(dedupeKey);
                    }
                    processedPractitionerIds.add(practitionerId);
                    toInsert.add(hp);
                }
            }
    
            /* -------------------------
               Insert in Batches of 50
            -------------------------- */
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

                        HealthcarePractitionerFacility failedHp = toInsert[i];

                        errorLogs.add(new Error_Log__c(
                            Object_API_Name__c    = 'HealthcarePractitionerFacility',
                            Error_Message__c      = String.join(errorMessages, '\n'),
                            Record_External_Id__c = failedHp.PractitionerId__c,
                            Context__c            = 'parseAndInsertPractitioners',
                            Stack_Trace__c        = 'AccountId: ' + failedHp.AccountId +
                                                    ' | PractitionerId: ' + failedHp.PractitionerId__c
                        ));
                    }
                }

                if (!errorLogs.isEmpty()) {
                    Database.insert(errorLogs, false);
                    System.debug('⚠️ Failed HealthcarePractitionerFacility inserts logged: ' + errorLogs.size());
                }

                System.debug('✅ Inserted HealthcarePractitionerFacility records: ' + successCount +
                             ' | Failed: ' + (toInsert.size() - successCount));
            }
    
        } catch (Exception e) {
            System.debug('❌ Error parsing Practitioner: ' + e.getMessage());
        }
    }

/* -------------------------
   Helper: build Practitioner dedupe key
-------------------------- */
private static String buildPractitionerDedupeKey(String name, String phone) {
    String namePart  = String.isBlank(name)  ? '' : name.trim().toLowerCase();
    String phonePart = String.isBlank(phone) ? '' : phone.trim();
    if (String.isBlank(namePart) && String.isBlank(phonePart)) return null;
    return namePart + '|' + phonePart;
}
    
      private static void insertInBatches(
        List<HealthcarePractitionerFacility> records,
        Integer batchSize
    ) {
        if (records == null || records.isEmpty()) return;
    
        List<HealthcarePractitionerFacility> buffer =
            new List<HealthcarePractitionerFacility>();
    
        for (HealthcarePractitionerFacility hp : records) {
            buffer.add(hp);
    
            if (buffer.size() == batchSize) {
                Database.insert(buffer, false);
                buffer.clear();
            }
        }
    
        if (!buffer.isEmpty()) {
            Database.insert(buffer, false);
        }
    }
    
        
    private static HealthcarePractitionerFacility parseSinglePractitioner(
        Map<String, Object> resource
    ) {
        if (resource == null) return null;
    
        HealthcarePractitionerFacility hp =
            new HealthcarePractitionerFacility();
    
        /* -------------------------
           Practitioner Id
        -------------------------- */
        hp.PractitionerId__c = (String) resource.get('id');
    
        /* -------------------------
           Active
        -------------------------- */
        if (resource.containsKey('active')) {
            hp.IsActive = (Boolean) resource.get('active');
        }
    
        /* -------------------------
           Name (given + family)
        -------------------------- */
        List<Object> names = (List<Object>) resource.get('name');
        if (names != null && !names.isEmpty()) {
            Map<String, Object> nameObj =
                (Map<String, Object>) names[0];
    
            List<Object> givenList =
                (List<Object>) nameObj.get('given');
            String family = (String) nameObj.get('family');
    
            List<String> parts = new List<String>();
    
            if (givenList != null) {
                for (Object g : givenList) {
                    if (g != null) parts.add(String.valueOf(g));
                }
            }
    
            if (!String.isBlank(family)) {
                parts.add(family);
            }
    
            if (!parts.isEmpty()) {
                hp.Name = String.join(parts, ' ');
            }
        }
    
        /* -------------------------
           Telecom (Phone / Email)
        -------------------------- */
        List<Object> telecoms =
            (List<Object>) resource.get('telecom');
        if (telecoms != null) {
            for (Object t : telecoms) {
                if (!(t instanceof Map<String, Object>)) continue;
                Map<String, Object> tel =
                    (Map<String, Object>) t;
    
                String systemtd = (String) tel.get('system');
                String value = (String) tel.get('value');
                if (String.isBlank(value)) continue;
    
                if ('phone'.equals(systemtd)) {
                    hp.Phone__c = value;
                } else if ('email'.equals(systemtd)) {
                    hp.Email__c = value;
                }
            }
        }
    
        /* -------------------------
           Address
        -------------------------- */
                           if (resource.containsKey('address')) {
                        List<Object> addresses = (List<Object>) resource.get('address');
                        if (addresses != null && !addresses.isEmpty()) {
                            Map<String, Object> addr = (Map<String, Object>) addresses[0];
                            List<String> streetLines = new List<String>();
                            if (addr.containsKey('line')) {
                                List<Object> lines = (List<Object>) addr.get('line');
                                for (Object l : lines) {
                                    if (l != null) streetLines.add(String.valueOf(l));
                                }
                            }
                            hp.Address__Street__s = streetLines.isEmpty() ? null : String.join(streetLines, ', ');
                            hp.Address__City__s = (String) addr.get('city');
                            String rawState = (String) addr.get('state');
                            hp.Address__StateCode__s = StateNormalizer.normalize(rawState);
                            hp.Address__CountryCode__s = 'US';
                            hp.Address__PostalCode__s = (String) addr.get('postalCode');
                        }
                    }
    

        hp.Gender__c = (String) resource.get('gender');
    
        if (resource.get('birthDate') != null) {
            hp.Birthdate__c =
                Date.valueOf((String) resource.get('birthDate'));
        }
    
        List<Object> qualifications =
            (List<Object>) resource.get('qualification');
        if (qualifications != null && !qualifications.isEmpty()) {
            Map<String, Object> qual =
                (Map<String, Object>) qualifications[0];
    
            Object codeRaw = qual.get('code');
            if (codeRaw instanceof Map<String, Object>) {
                Map<String, Object> code =
                    (Map<String, Object>) codeRaw;
    
                Object codingRaw = code.get('coding');
                if (codingRaw instanceof List<Object>) {
                    List<Object> codings =
                        (List<Object>) codingRaw;
    
                    if (!codings.isEmpty()) {
                        Map<String, Object> coding =
                            (Map<String, Object>) codings[0];
    
                        hp.Qualification__c =
                            (String) coding.get('display');
                    }
                }
            }
        }
    
        return hp;
    }


    
    //-----------------Care Observation--------------------



    public static void parseAndInsertObservations(String rawJson) {
        if (String.isBlank(rawJson)) return;

        List<Map<String, Object>> observations = new List<Map<String, Object>>();
        Set<String> patientIds = new Set<String>();
        Set<String> orgIds = new Set<String>();

        Map<String, Object> json =
            (Map<String, Object>) JSON.deserializeUntyped(rawJson);

        if (json.get('resourceType') == 'Bundle') {
            List<Object> entries = (List<Object>) json.get('entry');
            if (entries != null) {
                for (Object e : entries) {
                    Map<String, Object> res =
                        (Map<String, Object>) ((Map<String, Object>) e).get('resource');

                    if (res != null && res.get('resourceType') == 'Observation') {
                        observations.add(res);

                        Map<String, Object> subj =
                            (Map<String, Object>) res.get('subject');
                        if (subj != null) {
                            String ref = (String) subj.get('reference');
                            if (ref != null && ref.startsWith('Patient/')) {
                                patientIds.add(ref.substring(8));
                            }
                        }

                        List<Object> perf = (List<Object>) res.get('performer');
                        if (perf != null) {
                            for (Object p : perf) {
                                String r =
                                    (String) ((Map<String, Object>) p).get('reference');
                                if (r != null && r.startsWith('Organization/')) {
                                    orgIds.add(r.substring(13));
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        } else if (json.get('resourceType') == 'Observation') {
            observations.add(json);
        }

        if (observations.isEmpty()) return;

        Map<String, Id> patientMap = new Map<String, Id>();
        Map<String, Id> orgMap = new Map<String, Id>();

        for (Account a : [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c IN :patientIds
              
        ]) {
            if (a.Metriport_Patient_Id__c != null)
                patientMap.put(a.Metriport_Patient_Id__c, a.Id);

        }

        Set<String> incomingObservationIds = new Set<String>();

for (Map<String, Object> res : observations) {
    if (res.get('id') != null) {
        incomingObservationIds.add((String) res.get('id'));
    }
}

        Set<String> existingObservationIds = new Set<String>();

if (!incomingObservationIds.isEmpty()) {
    for (CareObservation co : [
        SELECT ObservationId__c
        FROM CareObservation
        WHERE ObservationId__c IN :incomingObservationIds
    ]) {
        existingObservationIds.add(co.ObservationId__c);
    }
}
        
        Set<String> deletedObservationIds = new Set<String>();
        if (!incomingObservationIds.isEmpty()) {
            for (Deleted_Record_Audit__c del : [
                SELECT External_Id_Metriport__c
                FROM Deleted_Record_Audit__c
                WHERE Object_API_Name__c = 'CareObservation'
                  AND External_Id_Metriport__c IN :incomingObservationIds
            ]) {
                deletedObservationIds.add(del.External_Id_Metriport__c);
            }
        }

        /* -------------------------
           Dedup keys for Vitals (Name + Value_Quantity__c),
           Labs (Name + Value_Quantity__c),
           Social History (Name + EffectiveDateTime)
           Fetch existing composite keys from CareObservation
        -------------------------- */
        Set<String> existingVitalDedupeKeys    = new Set<String>();
        Set<String> existingLabDedupeKeys      = new Set<String>();
        Set<String> existingSocialDedupeKeys   = new Set<String>();

        Set<Id> obsPatientIds = new Set<Id>(patientMap.values());
        if (!obsPatientIds.isEmpty()) {
            for (CareObservation co : [
                SELECT Name, Value_Quantity__c, EffectiveDateTime, Category
                FROM CareObservation
                WHERE Category IN ('Vital-Signs', 'Laboratory', 'Social-History')
                  AND ObservedSubjectId IN :obsPatientIds
            ]) {
                if (co.Category == 'Vital-Signs') {
                    String key = buildObservationDedupeKey(co.Name, co.Value_Quantity__c, null);
                    if (!String.isBlank(key)) existingVitalDedupeKeys.add(key);
                } else if (co.Category == 'Laboratory') {
                    String key = buildObservationDedupeKey(co.Name, co.Value_Quantity__c, null);
                    if (!String.isBlank(key)) existingLabDedupeKeys.add(key);
                } else if (co.Category == 'Social-History') {
                    String key = buildObservationDedupeKey(co.Name, null, co.EffectiveDateTime);
                    if (!String.isBlank(key)) existingSocialDedupeKeys.add(key);
                }
            }
        }

        
        List<CareObservation> toInsert = new List<CareObservation>();
        Set<String> inFlightObsDedupeKeys = new Set<String>();

        for (Map<String, Object> res : observations) {
            
                String observationId = (String) res.get('id');

 
    if (existingObservationIds.contains(observationId)) {
        continue;
    }
            if (deletedObservationIds.contains(observationId)) {
        continue;
    }

            CareObservation obs = new CareObservation();

            obs.ObservationId__c = (String) res.get('id');
            
            
            obs.ObservationStatus = (String) res.get('status');
            obs.Category = mapObservationCategory(res);
            
            if (obs.Category == 'Vital-Signs' || obs.Category == 'Laboratory') {
                mapVitalSigns(res, obs);
            }
            
            obs.ValueInterpretation = mapObservationInterpretation(res);



            Map<String, Object> subj =
                (Map<String, Object>) res.get('subject');
            if (subj != null) {
                String ref = (String) subj.get('reference');
                if (ref != null && ref.startsWith('Patient/')) {
                    obs.ObservedSubjectId =
                        patientMap.get(ref.substring(8));
                }
            }

            List<Object> perf =
                (List<Object>) res.get('performer');
            if (perf != null) {
                for (Object p : perf) {
                    String ref =
                        (String) ((Map<String, Object>) p).get('reference');
                    if (ref != null && ref.startsWith('Organization/')) {
                        obs.ObserverId =
                            orgMap.get(ref.substring(13));
                        break;
                    }
                }
            }

            String name;

            if (obs.Category == 'Laboratory') {
                // For Lab: name from code.text, value from valueString
                Map<String, Object> code =
                    (Map<String, Object>) res.get('code');
                if (code != null) {
                    name = (String) code.get('text');
                    if (String.isBlank(name)) {
                        List<Object> coding = (List<Object>) code.get('coding');
                        if (coding != null && !coding.isEmpty()) {
                            name = (String) ((Map<String, Object>) coding[0]).get('display');
                        }
                    }
                }
                String valueStr = (String) res.get('valueString');
                if (!String.isBlank(valueStr)) {
                    obs.Observed_Value__c = valueStr;
                } else {
                    // fallback to valueCodeableConcept
                    Map<String, Object> valueCc = (Map<String, Object>) res.get('valueCodeableConcept');
                    if (valueCc != null) {
                        String ccText = (String) valueCc.get('text');
                        if (!String.isBlank(ccText)) {
                            obs.Observed_Value__c = ccText;
                        } else {
                            List<Object> ccCoding = (List<Object>) valueCc.get('coding');
                            if (ccCoding != null && !ccCoding.isEmpty()) {
                                obs.Observed_Value__c = (String) ((Map<String, Object>) ccCoding[0]).get('display');
                            }
                        }
                    }
                }
            } else {
            
            Map<String, Object> value =
                (Map<String, Object>) res.get('valueCodeableConcept');
            
            if (value != null) {
                name = (String) value.get('text');
            
                List<Object> coding =
                    (List<Object>) value.get('coding');
            
                if (coding != null && !coding.isEmpty()) {
                    if (coding.size() > 1) {
                        obs.Observed_Value__c =
                            (String) ((Map<String, Object>) coding[1]).get('display');
                    }
            
                    if (String.isBlank(name)) {
                        name =
                            (String) ((Map<String, Object>) coding[0]).get('display');
                    }
                }
            }
            
            if (String.isBlank(name)) {
                Map<String, Object> code =
                    (Map<String, Object>) res.get('code');
            
                if (code != null) {
                    List<Object> coding =
                        (List<Object>) code.get('coding');
            
                    if (coding != null && !coding.isEmpty()) {
                        name =
                            (String) ((Map<String, Object>) coding[0]).get('display');
                    }
                }
            }

            } // end non-Laboratory name resolution
            
            if (String.isBlank(name)) {
                name = 'Observation';
            }
            
            obs.Name = name;


            Map<String, Object> period =
                (Map<String, Object>) res.get('effectivePeriod');
            if (period != null) {
                obs.EffectiveDateTime =
                    parseGmt((String) period.get('start'));
                obs.EndDateTime =
                    parseGmt((String) period.get('end'));
            }
              if (obs.EffectiveDateTime == null && res.containsKey('effectiveDateTime')) {
                obs.EffectiveDateTime = parseGmt((String) res.get('effectiveDateTime'));
              }

            // Dedup by composite key based on category
            String obsDedupeKey = null;
            if (obs.Category == 'Vital-Signs') {
                obsDedupeKey = buildObservationDedupeKey(obs.Name, obs.Value_Quantity__c, null);
                if (!String.isBlank(obsDedupeKey) &&
                    (existingVitalDedupeKeys.contains(obsDedupeKey) || inFlightObsDedupeKeys.contains(obsDedupeKey))) {
                    System.debug('⏭️ Skipping Vital-Signs Observation (Composite Duplicate): ' + obsDedupeKey);
                    continue;
                }
            } else if (obs.Category == 'Laboratory') {
                obsDedupeKey = buildObservationDedupeKey(obs.Name, obs.Value_Quantity__c, null);
                if (!String.isBlank(obsDedupeKey) &&
                    (existingLabDedupeKeys.contains(obsDedupeKey) || inFlightObsDedupeKeys.contains(obsDedupeKey))) {
                    System.debug('⏭️ Skipping Laboratory Observation (Composite Duplicate): ' + obsDedupeKey);
                    continue;
                }
            } else if (obs.Category == 'Social-History') {
                obsDedupeKey = buildObservationDedupeKey(obs.Name, null, obs.EffectiveDateTime);
                if (!String.isBlank(obsDedupeKey) &&
                    (existingSocialDedupeKeys.contains(obsDedupeKey) || inFlightObsDedupeKeys.contains(obsDedupeKey))) {
                    System.debug('⏭️ Skipping Social-History Observation (Composite Duplicate): ' + obsDedupeKey);
                    continue;
                }
            }
            if (!String.isBlank(obsDedupeKey)) inFlightObsDedupeKeys.add(obsDedupeKey);

            // Skip "No Data Available" observation names
            if (!String.isBlank(obs.Name) && obs.Name.trim().equalsIgnoreCase('No Data Available')) {
                System.debug('⏭️ Skipping Observation (No Data Available name): ' + observationId);
                continue;
            }

            toInsert.add(obs);
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

                    CareObservation failedObs = toInsert[i];

                    errorLogs.add(new Error_Log__c(
                        Object_API_Name__c    = 'CareObservation',
                        Error_Message__c      = String.join(errorMessages, '\n'),
                        Record_External_Id__c = failedObs.ObservationId__c,
                        Context__c            = 'parseAndInsertObservations',
                        Stack_Trace__c        = 'ObservedSubjectId: ' + failedObs.ObservedSubjectId +
                                                ' | ObservationId: ' + failedObs.ObservationId__c
                    ));
                }
            }

            if (!errorLogs.isEmpty()) {
                Database.insert(errorLogs, false);
                System.debug('⚠️ Failed CareObservation inserts logged: ' + errorLogs.size());
            }

            System.debug('✅ Inserted CareObservation records: ' + successCount +
                         ' | Failed: ' + (toInsert.size() - successCount));
        }
    }

/* -------------------------
   Helper: build Observation dedupe key
-------------------------- */
private static String buildObservationDedupeKey(String name, String valueQty, Datetime effectiveDt) {
    String namePart  = String.isBlank(name)     ? '' : name.trim().toLowerCase();
    String valuePart = String.isBlank(valueQty) ? '' : valueQty.trim().toLowerCase();
    String dtPart    = (effectiveDt != null)     ? String.valueOf(effectiveDt) : '';
    if (String.isBlank(namePart) && String.isBlank(valuePart) && String.isBlank(dtPart)) return null;
    return namePart + '|' + valuePart + '|' + dtPart;
}
    
        private static String mapObservationCategory(Map<String, Object> res) {
        List<Object> categories =
            (List<Object>) res.get('category');
    
        if (categories == null || categories.isEmpty()) {
            return null;
        }
    
        Map<String, Object> cat =
            (Map<String, Object>) categories[0];
    
        String rawValue;
    
        rawValue = (String) cat.get('text');
    
        if (String.isBlank(rawValue)) {
            List<Object> coding =
                (List<Object>) cat.get('coding');
            if (coding != null && !coding.isEmpty()) {
                rawValue =
                    (String) ((Map<String, Object>) coding[0]).get('display');
            }
        }
    
        if (String.isBlank(rawValue)) {
            return null;
        }
    
        String normalized =
            rawValue.toLowerCase()
                    .replace('-', '')
                    .replace(' ', '');
    
        if (normalized.contains('socialhistory')) {
            return 'Social-History';
        }
        if (normalized.contains('vitalsign')) {
            return 'Vital-Signs';
        }
         if (normalized.contains('laboratory') ||
            normalized.contains('lab')) {
            return 'Laboratory';
        }
            
    
        return null;
    }
    
    private static String mapObservationInterpretation(
        Map<String, Object> res
    ) {
        List<Object> interpretations =
            (List<Object>) res.get('interpretation');
    
        if (interpretations == null || interpretations.isEmpty()) {
            return null;
        }
    
        for (Object o : interpretations) {
            Map<String, Object> interp =
                (Map<String, Object>) o;
    
            String raw =
                (String) interp.get('text');
    
            if (String.isBlank(raw)) {
                List<Object> coding =
                    (List<Object>) interp.get('coding');
                if (coding != null && !coding.isEmpty()) {
                    raw =
                        (String) ((Map<String, Object>) coding[0]).get('code');
                }
            }
    
            if (String.isBlank(raw)) continue;
    
            String normalized =
                raw.toLowerCase();
    
            if (normalized == 'normal' || normalized == 'n') {
                return 'Normal';
            }
    
            if (normalized == 'high' ||
                normalized == 'hi' ||
                normalized == 'hh' ||
                normalized.contains('high')) {
                return 'High';
            }
    
            if (normalized == 'low' ||
                normalized == 'l' ||
                normalized == 'll' ||
                normalized.contains('low')) {
                return 'Low';
            }
        }
    
        return null;
    }

		
    private static String formatValueUnit(Map<String, Object> q) {
        if (q == null) return null;
    
        Object value = q.get('value');
        String unit = (String) q.get('unit');
    
        if (value == null) return null;
    
        return unit != null
            ? String.valueOf(value) + ' ' + unit
            : String.valueOf(value);
    }
    
    private static void mapVitalSigns(
            Map<String, Object> res,
            CareObservation obs
        ) {
            Map<String, Object> valueQty =
                (Map<String, Object>) res.get('valueQuantity');
        
            obs.Value_Quantity__c =
                formatValueUnit(valueQty);
        
            List<Object> ranges =
                (List<Object>) res.get('referenceRange');
        
            if (ranges != null && !ranges.isEmpty()) {
                Map<String, Object> range =
                    (Map<String, Object>) ranges[0];
        
                obs.Range_Low__c =
                    formatValueUnit(
                        (Map<String, Object>) range.get('low')
                    );
        
                obs.Range_High__c =
                    formatValueUnit(
                        (Map<String, Object>) range.get('high')
                    );
            }
        }



    private static DateTime parseGmt(String s) {
        if (String.isBlank(s)) return null;
    
        Integer dot = s.indexOf('.');
        if (dot > 0) {
            s = s.substring(0, dot);
        }
    
        if (s.endsWith('Z')) {
            s = s.substring(0, s.length() - 1);
        }
    
        s = s.replace('T', ' ');
    
        return DateTime.valueOfGmt(s);
    }


//---------------Diagnostic Report--------------------

    public static void parseAndInsertDiagnosticReports(String rawJson) {
        if (String.isBlank(rawJson)) return;

        List<Map<String, Object>> reports = new List<Map<String, Object>>();
        Set<String> patientIds = new Set<String>();
        Set<String> encounterIds = new Set<String>();
        Set<String> observationIds = new Set<String>();

        Map<String, Object> json =
            (Map<String, Object>) JSON.deserializeUntyped(rawJson);

        if ('Bundle'.equals(json.get('resourceType'))) {
            List<Object> entries = (List<Object>) json.get('entry');
            if (entries != null) {
                for (Object e : entries) {
                    Map<String, Object> res =
                        (Map<String, Object>) ((Map<String, Object>) e).get('resource');

                    if (res != null && res.get('resourceType') == 'DiagnosticReport') {
                        reports.add(res);
                        collectRefs(res, patientIds, encounterIds, observationIds);
                    }
                }
            }
        } else if ('DiagnosticReport'.equals(json.get('resourceType'))) {
            reports.add(json);
            collectRefs(json, patientIds, encounterIds, observationIds);
        }

        if (reports.isEmpty()) return;

        Map<String, Id> patientMap = new Map<String, Id>();
        for (Account a : [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c IN :patientIds
        ]) {
            patientMap.put(a.Metriport_Patient_Id__c, a.Id);
        }

        Map<String, Id> visitMap = new Map<String, Id>();
        for (Visit v : [
            SELECT Id, VisitId__c
            FROM Visit
            WHERE VisitId__c IN :encounterIds
        ]) {
            visitMap.put(v.VisitId__c, v.Id);
        }

        Map<String, Id> observationMap = new Map<String, Id>();
        for (CareObservation co : [
            SELECT Id, ObservationId__c
            FROM CareObservation
            WHERE ObservationId__c IN :observationIds
        ]) {
            observationMap.put(co.ObservationId__c, co.Id);
        }

        Set<String> incomingReportIds = new Set<String>();

        for (Map<String, Object> res : reports) {
            if (res.get('id') != null) {
                incomingReportIds.add((String) res.get('id'));
            }
        }
        
                Set<String> existingReportIds = new Set<String>();
        
        if (!incomingReportIds.isEmpty()) {
            for (DiagnosticSummary ds : [
                SELECT DiagnosticReportId__c
                FROM DiagnosticSummary
                WHERE DiagnosticReportId__c IN :incomingReportIds
            ]) {
                existingReportIds.add(ds.DiagnosticReportId__c);
            }
        }
        
           Set<String> deletedReportIds = new Set<String>();
    if (!incomingReportIds.isEmpty()) {
        for (Deleted_Record_Audit__c del : [
            SELECT External_Id_Metriport__c
            FROM Deleted_Record_Audit__c
            WHERE Object_API_Name__c = 'DiagnosticSummary'
              AND External_Id_Metriport__c IN :incomingReportIds
        ]) {
            deletedReportIds.add(del.External_Id_Metriport__c);
        }
    }

        /* -------------------------
           Dedup key: CareObservationId + Summary
           Fetch existing composite keys from DiagnosticSummary
        -------------------------- */
        Set<Id> diagPatientIds = new Set<Id>(patientMap.values());
        Set<String> existingDiagDedupeKeys = new Set<String>();
        if (!diagPatientIds.isEmpty()) {
            for (DiagnosticSummary ds : [
                SELECT CareObservationId, Summary
                FROM DiagnosticSummary
                WHERE CareObservationId != null
                  AND PatientId IN :diagPatientIds
            ]) {
                String key = buildDiagnosticDedupeKey(ds.CareObservationId, ds.Summary);
                if (!String.isBlank(key)) existingDiagDedupeKeys.add(key);
            }
        }

        
        
        List<DiagnosticSummary> toInsert = new List<DiagnosticSummary>();
        Set<String> inFlightDiagDedupeKeys = new Set<String>();

        for (Map<String, Object> res : reports) {
            
                String reportId = (String) res.get('id');

            if (existingReportIds.contains(reportId) ||
            deletedReportIds.contains(reportId)) {
            continue;
        }

            DiagnosticSummary ds = new DiagnosticSummary();

            ds.DiagnosticReportId__c = (String) res.get('id');
            ds.Status = (String) res.get('status');
            
            ds.Name__c = getDiagnosticReportName(res);

            List<Object> categories = (List<Object>) res.get('category');
            if (categories != null && !categories.isEmpty()) {
                ds.Summary =
                    (String) ((Map<String, Object>) categories[0]).get('text');
            }

            Map<String, Object> period =
                (Map<String, Object>) res.get('effectivePeriod');
            if (period != null) {
                ds.EffectiveStartDateTime =
                    parseGmt((String) period.get('start'));
                ds.EffectiveEndDateTime =
                    parseGmt((String) period.get('end'));
            }

            Map<String, Object> subj =
                (Map<String, Object>) res.get('subject');
            if (subj != null) {
                String ref = (String) subj.get('reference');
                if (ref != null && ref.startsWith('Patient/')) {
                    ds.PatientId =
                        patientMap.get(ref.substring(8));
                }
            }

            Map<String, Object> enc =
                (Map<String, Object>) res.get('encounter');
            if (enc != null) {
                String ref = (String) enc.get('reference');
                if (ref != null && ref.startsWith('Encounter/')) {
                    ds.Encounter__c =
                        visitMap.get(ref.substring(10));
                }
            }

            List<Object> results =
                (List<Object>) res.get('result');
            if (results != null && !results.isEmpty()) {
                String ref =
                    (String) ((Map<String, Object>) results[0]).get('reference');
                if (ref != null && ref.startsWith('Observation/')) {
                    ds.CareObservationId =
                        observationMap.get(ref.substring(12));
                }
            }

            // Dedup by composite key: CareObservationId + Summary
            String dedupeKey = buildDiagnosticDedupeKey(ds.CareObservationId, ds.Summary);
            if (!String.isBlank(dedupeKey)) {
                if (existingDiagDedupeKeys.contains(dedupeKey) || inFlightDiagDedupeKeys.contains(dedupeKey)) {
                    System.debug('⏭️ Skipping DiagnosticSummary (Composite Duplicate): ' + dedupeKey);
                    continue;
                }
                inFlightDiagDedupeKeys.add(dedupeKey);
            }

            // Skip "No Data Available" diagnostic report names
            if (!String.isBlank(ds.Name__c) && ds.Name__c.trim().equalsIgnoreCase('No Data Available')) {
                System.debug('⏭️ Skipping DiagnosticSummary (No Data Available name): ' + reportId);
                continue;
            }

            toInsert.add(ds);
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

                    DiagnosticSummary failedDs = toInsert[i];

                    errorLogs.add(new Error_Log__c(
                        Object_API_Name__c    = 'DiagnosticSummary',
                        Error_Message__c      = String.join(errorMessages, '\n'),
                        Record_External_Id__c = failedDs.DiagnosticReportId__c,
                        Context__c            = 'parseAndInsertDiagnosticReports',
                        Stack_Trace__c        = 'PatientId: ' + failedDs.PatientId +
                                                ' | DiagnosticReportId: ' + failedDs.DiagnosticReportId__c
                    ));
                }
            }

            if (!errorLogs.isEmpty()) {
                Database.insert(errorLogs, false);
                System.debug('⚠️ Failed DiagnosticSummary inserts logged: ' + errorLogs.size());
            }

            System.debug('✅ Inserted DiagnosticSummary records: ' + successCount +
                         ' | Failed: ' + (toInsert.size() - successCount));
        }
    }

/* -------------------------
   Helper: build DiagnosticSummary dedupe key
-------------------------- */
private static String buildDiagnosticDedupeKey(Id careObservationId, String summary) {
    String obsPart     = (careObservationId != null) ? String.valueOf(careObservationId) : '';
    String summaryPart = String.isBlank(summary) ? '' : summary.trim().toLowerCase();
    if (String.isBlank(obsPart) && String.isBlank(summaryPart)) return null;
    return obsPart + '|' + summaryPart;
}
    
    private static String getDiagnosticReportName(Map<String, Object> res) {
            Map<String, Object> code =
                (Map<String, Object>) res.get('code');
        
            if (code == null) {
                return 'Diagnostic Report';
            }
        
            String name = (String) code.get('text');
        
            if (String.isBlank(name)) {
                List<Object> coding =
                    (List<Object>) code.get('coding');
        
                if (coding != null && !coding.isEmpty()) {
                    name =
                        (String) ((Map<String, Object>) coding[0]).get('display');
                }
            }
        
            return String.isBlank(name)
                ? 'Diagnostic Report'
                : name;
        }


    private static void collectRefs(
        Map<String, Object> res,
        Set<String> patientIds,
        Set<String> encounterIds,
        Set<String> observationIds
    ) {
        Map<String, Object> subj =
            (Map<String, Object>) res.get('subject');
        if (subj != null) {
            String ref = (String) subj.get('reference');
            if (ref != null && ref.startsWith('Patient/')) {
                patientIds.add(ref.substring(8));
            }
        }

        Map<String, Object> enc =
            (Map<String, Object>) res.get('encounter');
        if (enc != null) {
            String ref = (String) enc.get('reference');
            if (ref != null && ref.startsWith('Encounter/')) {
                encounterIds.add(ref.substring(10));
            }
        }

        List<Object> results =
            (List<Object>) res.get('result');
        if (results != null) {
            for (Object r : results) {
                String ref =
                    (String) ((Map<String, Object>) r).get('reference');
                if (ref != null && ref.startsWith('Observation/')) {
                    observationIds.add(ref.substring(12));
                }
            }
        }
    }

	
    //--------------- Care plan--------------------
 

    public static void parseAndInsertCarePlans(String rawJson) {
        if (String.isBlank(rawJson)) return;

        List<Map<String, Object>> carePlans = new List<Map<String, Object>>();
        Set<String> patientIds = new Set<String>();

        Map<String, Object> json =
            (Map<String, Object>) JSON.deserializeUntyped(rawJson);

        if ('Bundle'.equals(json.get('resourceType'))) {
            List<Object> entries = (List<Object>) json.get('entry');
            if (entries != null) {
                for (Object e : entries) {
                    Map<String, Object> res =
                        (Map<String, Object>) ((Map<String, Object>) e).get('resource');

                    if (res != null && res.get('resourceType') == 'CarePlan') {
                        carePlans.add(res);
                        collectPatientId(res, patientIds);
                    }
                }
            }
        } else if ('CarePlan'.equals(json.get('resourceType'))) {
            carePlans.add(json);
            collectPatientId(json, patientIds);
        }

        if (carePlans.isEmpty()) return;

        Map<String, Id> patientMap = new Map<String, Id>();

        for (Account a : [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c IN :patientIds
        ]) {
            patientMap.put(a.Metriport_Patient_Id__c, a.Id);
        }

        Set<String> incomingCarePlanIds = new Set<String>();

        for (Map<String, Object> res : carePlans) {
            if (res.get('id') != null) {
                incomingCarePlanIds.add((String) res.get('id'));
            }
        }
        
                Set<String> existingCarePlanIds = new Set<String>();
        
        if (!incomingCarePlanIds.isEmpty()) {
            for (CareProgram cp : [
                SELECT CarePlanId__c
                FROM CareProgram
                WHERE CarePlanId__c IN :incomingCarePlanIds
            ]) {
                existingCarePlanIds.add(cp.CarePlanId__c);
            }
        }
        
        Set<String> deletedCarePlanIds = new Set<String>();
        if (!incomingCarePlanIds.isEmpty()) {
            for (Deleted_Record_Audit__c del : [
                SELECT External_Id_Metriport__c
                FROM Deleted_Record_Audit__c
                WHERE Object_API_Name__c = 'CareProgram'
                  AND External_Id_Metriport__c IN :incomingCarePlanIds
            ]) {
                deletedCarePlanIds.add(del.External_Id_Metriport__c);
            }
        }

        
        List<CareProgram> toInsert = new List<CareProgram>();

        for (Map<String, Object> res : carePlans) {
            
                String carePlanId = (String) res.get('id');

           if (existingCarePlanIds.contains(carePlanId) ||
                deletedCarePlanIds.contains(carePlanId)) {
                continue;
            }

            CareProgram cp = new CareProgram();

            cp.CarePlanId__c = (String) res.get('id');
            cp.Name = (String) res.get('description');
            cp.Status = (String) res.get('status');

            Map<String, Object> subj =
                (Map<String, Object>) res.get('subject');
            if (subj != null) {
                String ref = (String) subj.get('reference');
                if (ref != null && ref.startsWith('Patient/')) {
                    cp.Patient__c =
                        patientMap.get(ref.substring(8));
                }
            }

            Map<String, Object> period =
                (Map<String, Object>) res.get('period');
            if (period != null) {
                cp.StartDate =
                    parseDateOnly((String) period.get('start'));
            }

            toInsert.add(cp);
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

                    CareProgram failedCp = toInsert[i];

                    errorLogs.add(new Error_Log__c(
                        Object_API_Name__c    = 'CareProgram',
                        Error_Message__c      = String.join(errorMessages, '\n'),
                        Record_External_Id__c = failedCp.CarePlanId__c,
                        Context__c            = 'parseAndInsertCarePlans',
                        Stack_Trace__c        = 'Patient__c: ' + failedCp.Patient__c +
                                                ' | CarePlanId: ' + failedCp.CarePlanId__c
                    ));
                }
            }

            if (!errorLogs.isEmpty()) {
                Database.insert(errorLogs, false);
                System.debug('⚠️ Failed CareProgram inserts logged: ' + errorLogs.size());
            }

            System.debug('✅ Inserted CareProgram records: ' + successCount +
                         ' | Failed: ' + (toInsert.size() - successCount));
        }
    }

    private static void collectPatientId(
        Map<String, Object> res,
        Set<String> patientIds
    ) {
        Map<String, Object> subj =
            (Map<String, Object>) res.get('subject');
        if (subj != null) {
            String ref = (String) subj.get('reference');
            if (ref != null && ref.startsWith('Patient/')) {
                patientIds.add(ref.substring(8));
            }
        }
    }

    private static Date parseDateOnly(String s) {
        if (String.isBlank(s)) return null;

        Integer tIndex = s.indexOf('T');
        if (tIndex > 0) {
            s = s.substring(0, tIndex);
        }

        return Date.valueOf(s);
    }

	//----- Related Person-----------------

    
    public static void parseAndInsertRelatedPersons(String rawJson) {
        if (String.isBlank(rawJson)) return;
    
        List<Map<String, Object>> relatedPersons = new List<Map<String, Object>>();
        Set<String> patientIds = new Set<String>();
        Set<String> incomingRelatedPersonIds = new Set<String>();
    
        Map<String, Object> json =
            (Map<String, Object>) JSON.deserializeUntyped(rawJson);
    
        if ('Bundle'.equals(json.get('resourceType'))) {
            List<Object> entries = (List<Object>) json.get('entry');
            if (entries != null) {
                for (Object e : entries) {
                    Map<String, Object> res =
                        (Map<String, Object>) ((Map<String, Object>) e).get('resource');
    
                    if (res != null && 'RelatedPerson'.equals(res.get('resourceType'))) {
                        relatedPersons.add(res);
                        collectRelatedPatientId(res, patientIds);
                        if (res.containsKey('id') && res.get('id') != null) {
                            incomingRelatedPersonIds.add((String) res.get('id'));
                        }
                    }
                }
            }
        } else if ('RelatedPerson'.equals(json.get('resourceType'))) {
            relatedPersons.add(json);
            collectRelatedPatientId(json, patientIds);
            if (json.containsKey('id') && json.get('id') != null) {
                incomingRelatedPersonIds.add((String) json.get('id'));
            }
        }
    
        if (relatedPersons.isEmpty()) return;
    
        Set<String> existingRelatedPersonIds = new Set<String>();
        if (!incomingRelatedPersonIds.isEmpty()) {
            for (Contact c : [
                SELECT RelatedPersonId__c
                FROM Contact
                WHERE RelatedPersonId__c IN :incomingRelatedPersonIds
            ]) {
                existingRelatedPersonIds.add(c.RelatedPersonId__c);
            }
        }
        Set<String> deletedRelatedPersonIds = new Set<String>();
            if (!incomingRelatedPersonIds.isEmpty()) {
                for (Deleted_Record_Audit__c del : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE Object_API_Name__c = 'Contact'
                      AND External_Id_Metriport__c IN :incomingRelatedPersonIds
                ]) {
                    deletedRelatedPersonIds.add(del.External_Id_Metriport__c);
                }
            }
    
        Map<String, Id> patientAccountMap = new Map<String, Id>();
        Map<String, String> patientFirstNameMap = new Map<String, String>();
        Map<String, String> patientLastNameMap  = new Map<String, String>();
        if (!patientIds.isEmpty()) {
            for (Account a : [
                SELECT Id, Metriport_Patient_Id__c, FirstName, LastName
                FROM Account
                WHERE Metriport_Patient_Id__c IN :patientIds
            ]) {
                patientAccountMap.put(a.Metriport_Patient_Id__c, a.Id);
                patientFirstNameMap.put(a.Metriport_Patient_Id__c, a.FirstName != null ? a.FirstName.trim().toLowerCase() : '');
                patientLastNameMap.put(a.Metriport_Patient_Id__c,  a.LastName  != null ? a.LastName.trim().toLowerCase()  : '');
            }
        }

        /* -------------------------
           Dedup key: LastName + Phone (Name + Phone)
           Fetch existing composite keys from Contact (Related Person)
        -------------------------- */
        Set<Id> relatedPatientAccountIds = new Set<Id>(patientAccountMap.values());
        Set<String> existingRelatedPersonDedupeKeys = new Set<String>();
        if (!relatedPatientAccountIds.isEmpty()) {
            for (Contact c : [
                SELECT FirstName, LastName
                FROM Contact
                WHERE RecordType.DeveloperName = 'Related_Person'
                  AND LastName != null
                  AND Account__c IN :relatedPatientAccountIds
            ]) {
                String key = buildRelatedPersonDedupeKey(c.FirstName, c.LastName);
                if (!String.isBlank(key)) existingRelatedPersonDedupeKeys.add(key);
            }
        }
    
        List<Contact> toInsert = new List<Contact>();
        Set<String> inFlightRelatedPersonDedupeKeys = new Set<String>();
    
        for (Map<String, Object> res : relatedPersons) {
    
            String relatedPersonId = (String) res.get('id');
            if (existingRelatedPersonIds.contains(relatedPersonId) ||
                deletedRelatedPersonIds.contains(relatedPersonId)) {
                continue;
            }
            
            Id relatedPersonRtId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('Related_Person').getRecordTypeId();
    
            Contact c = new Contact();
    
            c.RelatedPersonId__c = relatedPersonId;
            
            c.RecordTypeId = relatedPersonRtId;
    
            List<Object> relList = (List<Object>) res.get('relationship');
            if (relList != null && !relList.isEmpty()) {
                Map<String, Object> rel = (Map<String, Object>) relList[0];
                c.Relationship__c = (String) rel.get('text');
            }
    
            if (res.containsKey('active') && res.get('active') != null) {
                c.Active__c = (Boolean) res.get('active');
            }
    
            List<Object> names = (List<Object>) res.get('name');
            if (names != null && !names.isEmpty()) {
                Map<String, Object> nameObj = (Map<String, Object>) names[0];
            
                List<Object> givenList = (List<Object>) nameObj.get('given');
                String family = (String) nameObj.get('family');
            
                if ((givenList != null && !givenList.isEmpty()) || !String.isBlank(family)) {
                    if (givenList != null && !givenList.isEmpty()) {
                        List<String> givenStrings = new List<String>();
                        for (Object g : givenList) {
                            if (g != null) givenStrings.add(String.valueOf(g));
                        }
                        c.FirstName = String.join(givenStrings, ' ');
                    }
            
                    if (!String.isBlank(family)) {
                        c.LastName = family;
                    }
                } else {
                    String fullName = (String) nameObj.get('text');
                    if (!String.isBlank(fullName)) {
                        List<String> parts = fullName.trim().split('\\s+');
                        if (parts.size() == 1) {
                            c.LastName = parts[0];
                        } else {
                            c.FirstName = parts[0];
            
                            String lastName = '';
                            for (Integer i = 1; i < parts.size(); i++) {
                                if (i > 1) lastName += ' ';
                                lastName += parts[i];
                            }
                            c.LastName = lastName;
                        }
                    }
                }
            
                if (String.isBlank(c.LastName)) {
                    c.LastName = 'Unknown';
                }
            }


    
            List<Object> telecoms = (List<Object>) res.get('telecom');
            if (telecoms != null) {
                for (Object tObj : telecoms) {
                    Map<String, Object> t = (Map<String, Object>) tObj;
                    String systemt = (String) t.get('system');
                    String value = (String) t.get('value');
                    if (!String.isBlank(systemt) && !String.isBlank(value)) {
                        if (systemt == 'phone' && String.isBlank(c.Phone)) {
                            c.Phone = value;
                        } else if (systemt == 'email' && String.isBlank(c.Email)) {
                            c.Email = value;
                        }
                    }
                }
            }
    
            if (res.containsKey('gender') && res.get('gender') != null) {
                c.GenderIdentity = (String) res.get('gender');
            }
    
            if (res.containsKey('birthDate') && res.get('birthDate') != null) {
                try {
                    c.Birthdate = Date.valueOf((String) res.get('birthDate'));
                } catch (Exception ex) {
                    System.debug('⚠️ Invalid birthDate: ' + res.get('birthDate'));
                }
            }
    
            List<Object> addresses = (List<Object>) res.get('address');
            if (addresses != null && !addresses.isEmpty()) {
                Map<String, Object> addr = (Map<String, Object>) addresses[0];
    
                List<Object> linesObj = (List<Object>) addr.get('line');
                String street = '';
                if (linesObj != null && !linesObj.isEmpty()) {
                    List<String> lineStrings = new List<String>();
                    for (Object l : linesObj) {
                        if (l != null) lineStrings.add(String.valueOf(l));
                    }
                    street = String.join(lineStrings, ' ');
                }
                
                c.MailingStreet = street;
                c.MailingCity = (String) addr.get('city');
                String rawState = (String) addr.get('state');
               c.MailingStateCode = StateNormalizer.normalize(rawState);
                c.MailingPostalCode = (String) addr.get('postalCode');
                c.MailingCountrycode = 'US';

            }
    
            Map<String, Object> patient = (Map<String, Object>) res.get('patient');
            if (patient != null) {
                String ref = (String) patient.get('reference');
                if (!String.isBlank(ref) && ref.startsWith('Patient/')) {
                    c.Account__c = patientAccountMap.get(ref.substring(8));
                }
            }

            // Skip if the related person has the same name as the patient
            Map<String, Object> patRef = (Map<String, Object>) res.get('patient');
            if (patRef != null) {
                String patFhirRef = (String) patRef.get('reference');
                if (!String.isBlank(patFhirRef) && patFhirRef.startsWith('Patient/')) {
                    String patFhirId = patFhirRef.substring(8);
                    String patFirst  = patientFirstNameMap.containsKey(patFhirId) ? patientFirstNameMap.get(patFhirId) : '';
                    String patLast   = patientLastNameMap.containsKey(patFhirId)  ? patientLastNameMap.get(patFhirId)  : '';
                    String cFirst    = String.isBlank(c.FirstName) ? '' : c.FirstName.trim().toLowerCase();
                    String cLast     = String.isBlank(c.LastName)  ? '' : c.LastName.trim().toLowerCase();
                    Boolean sameFullName = (cFirst == patFirst && cLast == patLast && !String.isBlank(cLast));
                    Boolean reverseMatch = (cFirst == patLast  && cLast == patFirst && !String.isBlank(cFirst));
                    if (sameFullName || reverseMatch) {
                        System.debug('⏭️ Skipping RelatedPerson (same name as patient): ' + relatedPersonId);
                        continue;
                    }
                }
            }

            // Dedup by composite key: LastName + Phone
            String dedupeKey = buildRelatedPersonDedupeKey(c.FirstName, c.LastName);
            if (!String.isBlank(dedupeKey)) {
                if (existingRelatedPersonDedupeKeys.contains(dedupeKey) || inFlightRelatedPersonDedupeKeys.contains(dedupeKey)) {
                    System.debug('⏭️ Skipping RelatedPerson (Composite Duplicate): ' + dedupeKey);
                    continue;
                }
                inFlightRelatedPersonDedupeKeys.add(dedupeKey);
            }
    
            // Skip "No Data Available" related person names
            if ((!String.isBlank(c.FirstName) && c.FirstName.trim().equalsIgnoreCase('No Data Available'))
                || (!String.isBlank(c.LastName) && c.LastName.trim().equalsIgnoreCase('No Data Available'))) {
                System.debug('⏭️ Skipping RelatedPerson (No Data Available name): ' + relatedPersonId);
                continue;
            }

            toInsert.add(c);
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

                    Contact failedContact = toInsert[i];

                    errorLogs.add(new Error_Log__c(
                        Object_API_Name__c    = 'Contact',
                        Error_Message__c      = String.join(errorMessages, '\n'),
                        Record_External_Id__c = failedContact.RelatedPersonId__c,
                        Context__c            = 'parseAndInsertRelatedPersons',
                        Stack_Trace__c        = 'Account__c: ' + failedContact.Account__c +
                                                ' | RelatedPersonId: ' + failedContact.RelatedPersonId__c
                    ));
                }
            }

            if (!errorLogs.isEmpty()) {
                Database.insert(errorLogs, false);
                System.debug('⚠️ Failed Contact inserts logged: ' + errorLogs.size());
            }

            System.debug('✅ Inserted RelatedPerson Contacts: ' + successCount +
                         ' | Failed: ' + (toInsert.size() - successCount));
        }
    }

/* -------------------------
   Helper: build RelatedPerson dedupe key
-------------------------- */
private static String buildRelatedPersonDedupeKey(String firstName, String lastName) {
    String firstPart = String.isBlank(firstName) ? '' : firstName.trim().toLowerCase();
    String lastPart  = String.isBlank(lastName)  ? '' : lastName.trim().toLowerCase();
  
    String fullName  = (firstPart + ' ' + lastPart).trim();
    if (String.isBlank(fullName)) return null;
    return fullName;
}
    
    private static void collectRelatedPatientId(
        Map<String, Object> res,
        Set<String> patientIds
    ) {
        Map<String, Object> patient =
            (Map<String, Object>) res.get('patient');
        if (patient != null) {
            String ref = (String) patient.get('reference');
            if (ref != null && ref.startsWith('Patient/')) {
                patientIds.add(ref.substring(8));
            }
        }
    }



//--------------- Service Request-----------


   public static void parseAndInsertServiceRequests(String rawJson) {
    if (String.isBlank(rawJson)) return;

    try {
        Map<String, Object> jsonData =
            (Map<String, Object>) JSON.deserializeUntyped(rawJson);

        List<Map<String, Object>> serviceRequests =
            new List<Map<String, Object>>();

        Set<String> patientFhirIds = new Set<String>();
        Set<String> orgIds = new Set<String>();

        if ('Bundle'.equals(jsonData.get('resourceType'))) {

            List<Object> entries =
                (List<Object>) jsonData.get('entry');
            if (entries == null) return;

            for (Object o : entries) {
                Map<String, Object> res =
                    (Map<String, Object>) ((Map<String, Object>) o)
                        .get('resource');

                if (res == null) continue;

                String rt = (String) res.get('resourceType');

                if (rt == 'ServiceRequest') {
                    serviceRequests.add(res);

                    Map<String, Object> requester =
                        (Map<String, Object>) res.get('requester');
                    if (requester != null) {
                        String ref =
                            (String) requester.get('reference');
                        if (ref != null && ref.startsWith('Organization/')) {
                            orgIds.add(ref.split('/')[1]);
                        }
                    }
                }

                if (rt == 'Patient') {
                    patientFhirIds.add((String) res.get('id'));
                }
            }
        }

        if (serviceRequests.isEmpty()) return;

        Map<String, Id> patientMap = new Map<String, Id>();
        Map<String, Id> orgMap = new Map<String, Id>();

        for (Account a : [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c IN :patientFhirIds
               
        ]) {
            if (a.Metriport_Patient_Id__c != null)
                patientMap.put(a.Metriport_Patient_Id__c, a.Id);

        }

        Set<String> incomingServiceRequestIds = new Set<String>();

for (Map<String, Object> res : serviceRequests) {
    if (res.get('id') != null) {
        incomingServiceRequestIds.add((String) res.get('id'));
    }
}

        Set<String> existingServiceRequestIds = new Set<String>();

if (!incomingServiceRequestIds.isEmpty()) {
    for (ClinicalServiceRequest csr : [
        SELECT Service_Request_Id__c
        FROM ClinicalServiceRequest
        WHERE Service_Request_Id__c IN :incomingServiceRequestIds
    ]) {
        existingServiceRequestIds.add(csr.Service_Request_Id__c);
    }
}
        Set<String> deletedServiceRequestIds = new Set<String>();

if (!incomingServiceRequestIds.isEmpty()) {
    for (Deleted_Record_Audit__c del : [
        SELECT External_Id_Metriport__c
        FROM Deleted_Record_Audit__c
        WHERE Object_API_Name__c = 'ClinicalServiceRequest'
        AND External_Id_Metriport__c IN :incomingServiceRequestIds
    ]) {
        deletedServiceRequestIds.add(del.External_Id_Metriport__c);
    }
}

        /* -------------------------
           Dedup key: Request_Name__c + StartDate
           Fetch existing composite keys from ClinicalServiceRequest
        -------------------------- */
        Set<Id> srPatientIds = new Set<Id>(patientMap.values());
        Set<String> existingSRDedupeKeys = new Set<String>();
        if (!srPatientIds.isEmpty()) {
            for (ClinicalServiceRequest csr : [
                SELECT Request_Name__c, StartDate
                FROM ClinicalServiceRequest
                WHERE Request_Name__c != null
                  AND PatientId IN :srPatientIds
            ]) {
                String key = buildServiceRequestDedupeKey(csr.Request_Name__c, csr.StartDate);
                if (!String.isBlank(key)) existingSRDedupeKeys.add(key);
            }
        }

        
        List<ClinicalServiceRequest> toInsert =
            new List<ClinicalServiceRequest>();
        Set<String> inFlightSRDedupeKeys = new Set<String>();

        for (Map<String, Object> res : serviceRequests) {
        
            String srId = (String) res.get('id');
        
           if (existingServiceRequestIds.contains(srId) ||
                deletedServiceRequestIds.contains(srId)) {
                continue;
            }
        
            ClinicalServiceRequest csr =
                parseSingleServiceRequest(
                    res, patientMap, orgMap
                );
        
            if (csr != null) {
                // Dedup by composite key: Request_Name__c + StartDate
                String dedupeKey = buildServiceRequestDedupeKey(csr.Request_Name__c, csr.StartDate);
                if (!String.isBlank(dedupeKey)) {
                    if (existingSRDedupeKeys.contains(dedupeKey) || inFlightSRDedupeKeys.contains(dedupeKey)) {
                        System.debug('⏭️ Skipping ServiceRequest (Composite Duplicate): ' + dedupeKey);
                        continue;
                    }
                    inFlightSRDedupeKeys.add(dedupeKey);
                }
                toInsert.add(csr);
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

                    ClinicalServiceRequest failedCsr = toInsert[i];

                    errorLogs.add(new Error_Log__c(
                        Object_API_Name__c    = 'ClinicalServiceRequest',
                        Error_Message__c      = String.join(errorMessages, '\n'),
                        Record_External_Id__c = failedCsr.Service_Request_Id__c,
                        Context__c            = 'parseAndInsertServiceRequests',
                        Stack_Trace__c        = 'PatientId: ' + failedCsr.PatientId +
                                                ' | ServiceRequestId: ' + failedCsr.Service_Request_Id__c
                    ));
                }
            }

            if (!errorLogs.isEmpty()) {
                Database.insert(errorLogs, false);
                System.debug('⚠️ Failed ClinicalServiceRequest inserts logged: ' + errorLogs.size());
            }

            System.debug('✅ Inserted ClinicalServiceRequest: ' + successCount +
                         ' | Failed: ' + (toInsert.size() - successCount));
        }

    } catch (Exception e) {
        System.debug(
            '❌ Error parsing ServiceRequest: ' +
            e.getMessage()
        );
    }
}

/* -------------------------
   Helper: build ServiceRequest dedupe key
-------------------------- */
private static String buildServiceRequestDedupeKey(String requestName, Datetime startDate) {
    String namePart = String.isBlank(requestName) ? '' : requestName.trim().toLowerCase();
    String datePart = (startDate != null) ? String.valueOf(startDate) : '';
    if (String.isBlank(namePart) && String.isBlank(datePart)) return null;
    return namePart + '|' + datePart;
}

	
    private static ClinicalServiceRequest parseSingleServiceRequest(
    Map<String, Object> resource,
    Map<String, Id> patientMap,
    Map<String, Id> orgMap
) {
    ClinicalServiceRequest csr =
        new ClinicalServiceRequest();

    csr.Service_Request_Id__c =
        (String) resource.get('id');

    csr.Status =
        (String) resource.get('status');
    csr.Type ='Plan';

    Map<String, Object> code =
        (Map<String, Object>) resource.get('code');
    if (code != null && code.containsKey('text')) {
        csr.Request_Name__c =
            (String) code.get('text');
    }

    if (!patientMap.isEmpty()) {
        csr.PatientId =
            patientMap.values().isEmpty()
                ? null
                : patientMap.values()[0];
    }

    Map<String, Object> requester =
        (Map<String, Object>) resource.get('requester');
    if (requester != null) {
        String ref =
            (String) requester.get('reference');
        if (ref != null && ref.startsWith('Organization/')) {
            csr.RequesterId =
                orgMap.get(ref.split('/')[1]);
        }
    }

    return csr;
}

//------------------Binary--------------------

        public static void parseBinaryAndUpdateAccount(String rawJson) {
            if (String.isBlank(rawJson)) return;
        
            try {
                Map<String, Object> jsonData =
                    (Map<String, Object>) JSON.deserializeUntyped(rawJson);
        
                if (jsonData.get('resourceType') != 'Bundle') return;
        
                List<Object> entries = (List<Object>) jsonData.get('entry');
                if (entries == null) return;
        
                String patientId;
                String decodedBinaryText;
        
                for (Object o : entries) {
                    Map<String, Object> resource =
                        (Map<String, Object>) ((Map<String, Object>) o).get('resource');
        
                    if (resource == null) continue;
        
                    String resourceType = (String) resource.get('resourceType');
        
                    if (resourceType == 'Patient') {
                        patientId = (String) resource.get('id');
                    }
        
                    if (resourceType == 'Binary') {
                        decodedBinaryText = decodeBinary(resource);
                    }
                }
        
                if (String.isBlank(patientId) || String.isBlank(decodedBinaryText)) {
                    System.debug('⚠️ Missing Patient or Binary data');
                    return;
                }
        
                Account acc = [
                    SELECT Id, Description
                    FROM Account
                    WHERE Metriport_Patient_Id__c = :patientId
                    LIMIT 1
                ];
        
                acc.Patient_Summary__c = decodedBinaryText;
                update acc;
        
                System.debug('✅ Updated Account with decoded Binary text');
        
            } catch (Exception e) {
                System.debug('❌ Error parsing Binary: ' + e.getMessage());
            }
        }
        
        private static String decodeBinary(Map<String, Object> binaryResource) {
            if (!binaryResource.containsKey('data')) return null;
        
            String base64Data = (String) binaryResource.get('data');
            if (String.isBlank(base64Data)) return null;
        
            Blob decodedBlob = EncodingUtil.base64Decode(base64Data);
            return decodedBlob.toString();
        }


	//-----------------Family Member History ------------------------
        
        public static void parseAndInsertFamilyMemberHistory(String rawJson) {
                if (String.isBlank(rawJson)) return;
        
                List<Map<String, Object>> histories = new List<Map<String, Object>>();
                Set<String> patientIds = new Set<String>();
                Set<String> historyIds = new Set<String>();
        
                Map<String, Object> json =
                    (Map<String, Object>) JSON.deserializeUntyped(rawJson);
        
                if ('Bundle'.equals(json.get('resourceType'))) {
                    List<Object> entries = (List<Object>) json.get('entry');
                    if (entries != null) {
                        for (Object e : entries) {
                            Map<String, Object> res =
                                (Map<String, Object>) ((Map<String, Object>) e).get('resource');
        
                            if (res != null &&
                                res.get('resourceType') == 'FamilyMemberHistory') {
        
                                histories.add(res);
        
                                if (res.get('id') != null) {
                                    historyIds.add((String) res.get('id'));
                                }
        
                                collectPatient(res, patientIds);
                            }
                        }
                    }
                } else if ('FamilyMemberHistory'.equals(json.get('resourceType'))) {
                    histories.add(json);
                    historyIds.add((String) json.get('id'));
                    collectPatient(json, patientIds);
                }
        
                if (histories.isEmpty()) return;
        
                Map<String, Id> patientMap = new Map<String, Id>();
        
                for (Account a : [
                    SELECT Id, Metriport_Patient_Id__c
                    FROM Account
                    WHERE Metriport_Patient_Id__c IN :patientIds
                ]) {
                    patientMap.put(a.Metriport_Patient_Id__c, a.Id);
                }
        
                Set<String> existingIds = new Set<String>();
        
                if (!historyIds.isEmpty()) {
                    for (Family_Member_History__c fmh : [
                        SELECT FamilyMemberHistoryId__c
                        FROM Family_Member_History__c
                        WHERE FamilyMemberHistoryId__c IN :historyIds
                    ]) {
                        existingIds.add(fmh.FamilyMemberHistoryId__c);
                    }
                }
            Set<String> deletedHistoryIds = new Set<String>();

            if (!historyIds.isEmpty()) {
                for (Deleted_Record_Audit__c del : [
                    SELECT External_Id_Metriport__c
                    FROM Deleted_Record_Audit__c
                    WHERE Object_API_Name__c = 'Family_Member_History__c'
                    AND External_Id_Metriport__c IN :historyIds
                ]) {
                    deletedHistoryIds.add(del.External_Id_Metriport__c);
                }
            }

            /* -------------------------
               Dedup key: Name (relationship text)
               Fetch existing composite keys from Family_Member_History__c
            -------------------------- */
            Set<Id> fmhPatientIds = new Set<Id>(patientMap.values());
            Set<String> existingFMHDedupeKeys = new Set<String>();
            if (!fmhPatientIds.isEmpty()) {
                for (Family_Member_History__c fmh : [
                    SELECT Name
                    FROM Family_Member_History__c
                    WHERE Name != null
                      AND Patient__c IN :fmhPatientIds
                ]) {
                    String key = buildFMHDedupeKey(fmh.Name);
                    if (!String.isBlank(key)) existingFMHDedupeKeys.add(key);
                }
            }
        
                List<Family_Member_History__c> toInsert =
                    new List<Family_Member_History__c>();
                Set<String> inFlightFMHDedupeKeys = new Set<String>();
        
                for (Map<String, Object> res : histories) {
        
                    String historyId = (String) res.get('id');
        
                   if (existingIds.contains(historyId) ||
    deletedHistoryIds.contains(historyId)) continue;
        
                    Family_Member_History__c fmh =
                        parseSingleFamilyMemberHistory(res, patientMap);
        
                    if (fmh != null) {
                        // Skip "No Data Available" family member names
                        if (!String.isBlank(fmh.Name) && fmh.Name.trim().equalsIgnoreCase('No Data Available')) {
                            System.debug('⏭️ Skipping FamilyMemberHistory (No Data Available name): ' + historyId);
                            continue;
                        }

                        // Dedup by composite key: Name
                        String dedupeKey = buildFMHDedupeKey(fmh.Name);
                        if (!String.isBlank(dedupeKey)) {
                            if (existingFMHDedupeKeys.contains(dedupeKey) || inFlightFMHDedupeKeys.contains(dedupeKey)) {
                                System.debug('⏭️ Skipping FamilyMemberHistory (Composite Duplicate): ' + dedupeKey);
                                continue;
                            }
                            inFlightFMHDedupeKeys.add(dedupeKey);
                        }
                        toInsert.add(fmh);
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

                            Family_Member_History__c failedFmh = toInsert[i];

                            errorLogs.add(new Error_Log__c(
                                Object_API_Name__c    = 'Family_Member_History__c',
                                Error_Message__c      = String.join(errorMessages, '\n'),
                                Record_External_Id__c = failedFmh.FamilyMemberHistoryId__c,
                                Context__c            = 'parseAndInsertFamilyMemberHistory',
                                Stack_Trace__c        = 'Patient__c: ' + failedFmh.Patient__c +
                                                        ' | FamilyMemberHistoryId: ' + failedFmh.FamilyMemberHistoryId__c
                            ));
                        }
                    }

                    if (!errorLogs.isEmpty()) {
                        Database.insert(errorLogs, false);
                        System.debug('⚠️ Failed Family_Member_History__c inserts logged: ' + errorLogs.size());
                    }

                    System.debug('✅ Inserted Family_Member_History__c records: ' + successCount +
                                 ' | Failed: ' + (toInsert.size() - successCount));
                }
            }

/* -------------------------
   Helper: build FamilyMemberHistory dedupe key
-------------------------- */
private static String buildFMHDedupeKey(String name) {
    String namePart = String.isBlank(name) ? '' : name.trim().toLowerCase();
    if (String.isBlank(namePart)) return null;
    return namePart;
}
        
            private static Family_Member_History__c parseSingleFamilyMemberHistory(
                Map<String, Object> res,
                Map<String, Id> patientMap
            ) {
                Family_Member_History__c fmh =
                    new Family_Member_History__c();
        
                fmh.FamilyMemberHistoryId__c =
                    (String) res.get('id');
        
                Map<String, Object> relationship =
                    (Map<String, Object>) res.get('relationship');
                
                if (relationship != null) {
                
                    String relText = (String) relationship.get('text');
                    if (!String.isBlank(relText)) {
                        fmh.Name = relText;
                    } else {
                        List<Object> coding =
                            (List<Object>) relationship.get('coding');
                
                        if (coding != null && !coding.isEmpty()) {
                            fmh.Name =
                                (String) ((Map<String, Object>) coding[0]).get('display');
                        }
                    }
                }

        
                fmh.Date__c =
                    parseDateOnly((String) res.get('date'));
        
                fmh.Birthdate__c =
                    parseBDateOnly((String) res.get('bornDate'));
        
                if (res.containsKey('deceasedBoolean')) {
                    fmh.Deceased__c =
                        (Boolean) res.get('deceasedBoolean');
                }
        
                Map<String, Object> deceasedAge =
                    (Map<String, Object>) res.get('deceasedAge');
        
                if (deceasedAge != null && deceasedAge.get('value') != null) {
                    fmh.Deceased_at_Age__c =
                        formatValueUnitts(deceasedAge);
                }
        
                List<Object> conditions =
                    (List<Object>) res.get('condition');
        
                if (conditions != null && !conditions.isEmpty()) {
                    Map<String, Object> cond =
                        (Map<String, Object>) conditions[0];
        
                    Map<String, Object> outcome =
                        (Map<String, Object>) cond.get('outcome');
        
                    if (outcome != null) {
                        List<Object> coding =
                            (List<Object>) outcome.get('coding');
        
                        if (coding != null && !coding.isEmpty()) {
                            fmh.Outcome__c =
                                (String) ((Map<String, Object>) coding[0]).get('display');
                        }
                    }
        
                    List<Object> notes =
                        (List<Object>) cond.get('note');
        
                    if (notes != null && !notes.isEmpty()) {
                        fmh.Note__c =
                            (String) ((Map<String, Object>) notes[0]).get('text');
                    }
                }
        
                if (String.isBlank(fmh.Note__c)) {
                    List<Object> notes =
                        (List<Object>) res.get('note');
        
                    if (notes != null && !notes.isEmpty()) {
                        fmh.Note__c =
                            (String) ((Map<String, Object>) notes[0]).get('text');
                    }
                }
        
                Map<String, Object> patient =
                    (Map<String, Object>) res.get('patient');
        
                if (patient != null) {
                    String ref = (String) patient.get('reference');
                    if (ref != null && ref.startsWith('Patient/')) {
                        fmh.Patient__c =
                            patientMap.get(ref.substring(8));
                    }
                }
        
                return fmh;
            }
        
            private static void collectPatient(
                Map<String, Object> res,
                Set<String> patientIds
            ) {
                Map<String, Object> patient =
                    (Map<String, Object>) res.get('patient');
        
                if (patient != null) {
                    String ref = (String) patient.get('reference');
                    if (ref != null && ref.startsWith('Patient/')) {
                        patientIds.add(ref.substring(8));
                    }
                }
            }
        
            private static Date parseBDateOnly(String s) {
                if (String.isBlank(s)) return null;
                Integer t = s.indexOf('T');
                if (t > 0) s = s.substring(0, t);
                return Date.valueOf(s);
            }
        
            private static String formatValueUnitts(Map<String, Object> q) {
                if (q == null) return null;
        
                Object value = q.get('value');
                String unit = (String) q.get('unit');
        
                if (value == null) return null;
        
                return unit != null
                    ? String.valueOf(value) + ' ' + unit
                    : String.valueOf(value);
            }

    
    public static void markAccountReadyToSend(String PatientId) {
        if (String.isBlank(PatientId)) {
            return;
        }
    
        List<Account> accountsToUpdate = [
            SELECT Id, Ready_to_Sent__c
            FROM Account
            WHERE Metriport_Patient_Id__c = :PatientId
            LIMIT 1
        ];
    
        if (accountsToUpdate.isEmpty()) {
            return;
        }
    
        Account acc = accountsToUpdate[0];
    
        if (!acc.Ready_to_Sent__c) {
            acc.Ready_to_Sent__c = true;
            update acc;
        }
    }



    

}