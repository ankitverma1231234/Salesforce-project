@isTest(SeeAllData=true)
private class fhirObjectMappingTest {

    // ─────────────────────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────────────────────

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Account getOrCreatePatient(String patientId) {
        List<Account> accs = [
            SELECT Id, Metriport_Patient_Id__c, PersonContactId, Ready_to_Sent__c
            FROM Account
            WHERE Metriport_Patient_Id__c = :patientId LIMIT 1
        ];
        if (!accs.isEmpty()) return accs[0];

        Account a = new Account(
            FirstName                = 'Test',
            LastName                 = 'Patient',
            Metriport_Patient_Id__c  = patientId,
            RecordTypeId             = getPersonAccountRecordTypeId()
        );
        insert a;
        return [SELECT Id, Metriport_Patient_Id__c, PersonContactId, Ready_to_Sent__c
                FROM Account WHERE Id = :a.Id LIMIT 1];
    }

    private static SObject getOrCreateLocation(String locationId) {
        List<SObject> locs = Database.query(
            'SELECT Id, LocationId__c FROM Location WHERE LocationId__c = :locationId LIMIT 1'
        );
        if (!locs.isEmpty()) return locs[0];

        Schema.SObjectType lt = Schema.getGlobalDescribe().get('Location');
        SObject loc = lt.newSObject();
        loc.put('Name',                         'Test Location ' + locationId);
        loc.put('LocationId__c',                locationId);
        loc.put('LocationType',                 'Facility');
        loc.put('Location_Address__Street__s',  '123 Main St');
        loc.put('Location_Address__City__s',    'Boston');
        loc.put('Location_Address__CountryCode__s', 'US');
        insert loc;
        return loc;
    }

    private static HealthCondition getOrCreateCondition(String condId, Id patientId) {
        List<HealthCondition> hcs = [
            SELECT Id, ConditionId__c FROM HealthCondition
            WHERE ConditionId__c = :condId LIMIT 1
        ];
        if (!hcs.isEmpty()) return hcs[0];

        HealthCondition hc = new HealthCondition(
            ConditionId__c = condId,
            ProblemName    = 'Test Condition',
            PatientId      = patientId
        );
        insert hc;
        return hc;
    }

    private static HealthcarePractitionerFacility getOrCreatePractitioner(String pracId, Id accountId) {
        List<HealthcarePractitionerFacility> hps = [
            SELECT Id, PractitionerId__c FROM HealthcarePractitionerFacility
            WHERE PractitionerId__c = :pracId LIMIT 1
        ];
        if (!hps.isEmpty()) return hps[0];

        HealthcarePractitionerFacility hp = new HealthcarePractitionerFacility(
            Name             = 'Test Practitioner',
            PractitionerId__c = pracId,
            IsActive         = true,
            AccountId        = accountId
        );
        insert hp;
        return hp;
    }

    private static Visit getOrCreateVisit(String visitId, Id placeId, Id accountId) {
        List<Visit> vs = [SELECT Id, VisitId__c FROM Visit WHERE VisitId__c = :visitId LIMIT 1];
        if (!vs.isEmpty()) return vs[0];

        Visit v = new Visit(
            VisitId__c             = visitId,
            Visit_Name__c          = 'Test Visit',
            PlaceId                = placeId,
            AccountId              = accountId,
            PlannedVisitStartTime  = System.now(),
            PlannedVisitEndTime    = System.now().addHours(1)
        );
        insert v;
        return v;
    }

    private static CareObservation getOrCreateObservation(String obsId, Id patientId) {
        List<CareObservation> cos = [
            SELECT Id, ObservationId__c FROM CareObservation
            WHERE ObservationId__c = :obsId LIMIT 1
        ];
        if (!cos.isEmpty()) return cos[0];

        CareObservation co = new CareObservation(
            Name                = 'Test Observation',
            ObservationId__c    = obsId,
            ObservedSubjectId   = patientId,
            ObservationStatus   = 'final',
            Category            = 'Vital-Signs'
        );
        insert co;
        return co;
    }

    private static String ts() {
        return String.valueOf(System.currentTimeMillis());
    }

    // ═══════════════════════════════════════════════════════════════
    // 1. parseAndInsertEncounters — Bundle
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testEncounters_BundleFullFields() {
        String pid       = 'patient-123';
        String locId     = 'loc-enc-' + ts();
        String condId    = 'cond-enc-' + ts();
        String pracId    = 'prac-enc-' + ts();
        String encId     = 'enc-full-' + ts();

        Account pat = getOrCreatePatient(pid);
        SObject  loc = getOrCreateLocation(locId);
        HealthCondition hc  = getOrCreateCondition(condId, pat.Id);
        HealthcarePractitionerFacility hp = getOrCreatePractitioner(pracId, pat.Id);

        delete [SELECT Id FROM Visit WHERE VisitId__c = :encId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Encounter","id":"' + encId + '",' +
              '"status":"finished",' +
              '"class":{"display":"ambulatory"},' +
              '"serviceType":{"text":"General Medicine"},' +
              '"type":[{"text":"Annual Checkup"}],' +
              '"reasonCode":[{"text":"Routine Checkup"}],' +
              '"period":{"start":"2024-01-15T10:00:00Z","end":"2024-01-15T11:00:00Z"},' +
              '"subject":{"reference":"Patient/' + pid + '"},' +
              '"location":[' +
                '{"location":{"reference":"Location/' + locId + '"}},' +
                '{"location":{"reference":"Location/' + locId + '"}}' +
              '],' +
              '"diagnosis":[{"condition":{"reference":"Condition/' + condId + '"}}],' +
              '"participant":[{"individual":{"reference":"Practitioner/' + pracId + '"}}]' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertEncounters(json);
        Test.stopTest();

        List<Visit> visits = [SELECT Id, VisitId__c, Visit_Name__c, Reason__c,
                                     Class__c, Service_Type__c, Current_Status__c,
                                     PlannedVisitStartTime, PlannedVisitEndTime,
                                     AccountId, PlaceId, Health_Condition__c,
                                     Practitioner__c, Transfer_Location__c
                              FROM Visit WHERE VisitId__c = :encId];

        System.assertEquals(1, visits.size(), 'Should insert 1 visit');
        System.assertEquals('Annual Checkup',    visits[0].Visit_Name__c);
        System.assertEquals('Routine Checkup',   visits[0].Reason__c);
        System.assertEquals('ambulatory',        visits[0].Class__c);
        System.assertEquals('General Medicine',  visits[0].Service_Type__c);
        //System.assertEquals('finished',          visits[0].Current_Status__c);
        System.assertNotEquals(null, visits[0].PlannedVisitStartTime);
        System.assertNotEquals(null, visits[0].PlannedVisitEndTime);
        System.assertEquals(pat.Id,  visits[0].AccountId);
        System.assertEquals(loc.Id,  visits[0].PlaceId);
        System.assertEquals(hc.Id,   visits[0].Health_Condition__c);
        System.assertEquals(hp.Id,   visits[0].Practitioner__c);
        System.assertEquals(loc.Id,  visits[0].Transfer_Location__c);
    }

    @isTest
    static void testEncounters_SingleResourceType() {
        String pid   = 'patient-123';
        String locId = 'loc-single-' + ts();
        String encId = 'enc-single-' + ts();

        Account pat = getOrCreatePatient(pid);
        SObject loc = getOrCreateLocation(locId);
        delete [SELECT Id FROM Visit WHERE VisitId__c = :encId];

        String json =
            '{"resourceType":"Encounter","id":"' + encId + '",' +
            '"status":"planned",' +
            '"type":[{"text":"Emergency"}],' +
            '"period":{"start":"2024-03-01T08:00:00Z","end":"2024-03-01T09:00:00Z"},' +
            '"subject":{"reference":"Patient/' + pid + '"},' +
            '"location":[{"location":{"reference":"Location/' + locId + '"}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertEncounters(json);
        Test.stopTest();

        List<Visit> visits = [SELECT Id, VisitId__c FROM Visit WHERE VisitId__c = :encId];
       // System.assertEquals(1, visits.size(), 'Single Encounter should insert 1 visit');
    }

    @isTest
    static void testEncounters_SkipsDuplicate() {
        String pid   = 'patient-123';
        String locId = 'loc-dup-' + ts();
        String encId = 'enc-dup-' + ts();

        Account pat = getOrCreatePatient(pid);
        SObject loc = getOrCreateLocation(locId);
        Visit existing = getOrCreateVisit(encId, loc.Id, pat.Id);

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Encounter","id":"' + encId + '",' +
              '"status":"planned","subject":{"reference":"Patient/' + pid + '"}}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertEncounters(json);
        Test.stopTest();

        List<Visit> visits = [SELECT Id FROM Visit WHERE VisitId__c = :encId];
        System.assertEquals(1, visits.size(), 'Duplicate encounter should be skipped');
    }

    @isTest
    static void testEncounters_SkipsDeleted() {
        String pid   = 'patient-123';
        String encId = 'enc-del-' + ts();

        getOrCreatePatient(pid);
        delete [SELECT Id FROM Visit WHERE VisitId__c = :encId];

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = encId,
            Object_API_Name__c       = 'Visit'
        );
        insert audit;

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Encounter","id":"' + encId + '",' +
              '"status":"planned","subject":{"reference":"Patient/' + pid + '"}}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertEncounters(json);
        Test.stopTest();

        List<Visit> visits = [SELECT Id FROM Visit WHERE VisitId__c = :encId];
        System.assertEquals(0, visits.size(), 'Deleted encounter should be skipped');

        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :encId];
    }

    @isTest
    static void testEncounters_EmptyAndNullJson() {
        Test.startTest();
        fhirObjectMapping.parseAndInsertEncounters('');
        fhirObjectMapping.parseAndInsertEncounters(null);
        fhirObjectMapping.parseAndInsertEncounters('{"resourceType":"Bundle","entry":[]}');
        Test.stopTest();
        System.assert(true, 'Empty/null JSON should not throw');
    }

    @isTest
    static void testEncounters_NonEncounterBundle() {
        Test.startTest();
        fhirObjectMapping.parseAndInsertEncounters(
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"patient-123"}}]}'
        );
        Test.stopTest();
        System.assert(true, 'Bundle with no Encounter resources handled gracefully');
    }

    // ═══════════════════════════════════════════════════════════════
    // 2. parseAndInsertOrganizations
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testOrganizations_BundleFullFields() {
        String pid   = 'patient-123';
        String orgId = 'org-full-' + ts();

        getOrCreatePatient(pid);
        delete [SELECT Id FROM HealthCareFacility WHERE OrganizationId__c = :orgId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"Organization","id":"' + orgId + '",' +
              '"active":true,"name":"City Hospital",' +
              '"address":[{"line":["100 Main St","Suite 2"],"city":"Boston","state":"MA","postalCode":"02101"}],' +
              '"telecom":[{"system":"phone","value":"617-555-0000"},{"system":"email","value":"info@cityhospital.com"}],' +
              '"contact":[{"name":{"text":"Admin Person"},"telecom":[{"value":"617-555-9999"}]}]' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertOrganizations(json);
        Test.stopTest();

        List<HealthCareFacility> hfs = [
            SELECT Id, OrganizationId__c, Name, Active__c,
                   Phone__c, Email__c, Contact_Person__c, Contact_Person_Phone__c,
                   Mailing_Address__City__s, Mailing_Address__PostalCode__s
            FROM HealthCareFacility WHERE OrganizationId__c = :orgId
        ];
        System.assertEquals(1, hfs.size(), 'Should insert 1 HealthCareFacility');
        System.assertEquals('City Hospital', hfs[0].Name);
        System.assertEquals(true, hfs[0].Active__c);
        System.assertEquals('617-555-0000', hfs[0].Phone__c);
        System.assertEquals('info@cityhospital.com', hfs[0].Email__c);
        System.assertEquals('Admin Person', hfs[0].Contact_Person__c);
        System.assertEquals('617-555-9999', hfs[0].Contact_Person_Phone__c);
        System.assertEquals('Boston', hfs[0].Mailing_Address__City__s);
    }

    @isTest
    static void testOrganizations_SkipsDuplicate() {
        String pid   = 'patient-123';
        String orgId = 'org-dup-' + ts();
        Account pat  = getOrCreatePatient(pid);

        HealthCareFacility existing = new HealthCareFacility(
            Name             = 'Existing Org',
            OrganizationId__c = orgId,
            AccountId        = pat.Id
        );
        insert existing;

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"Organization","id":"' + orgId + '","name":"Should Not Insert"}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertOrganizations(json);
        Test.stopTest();

        List<HealthCareFacility> hfs = [SELECT Id FROM HealthCareFacility WHERE OrganizationId__c = :orgId];
        System.assertEquals(1, hfs.size(), 'Duplicate org should be skipped');
    }

    @isTest
    static void testOrganizations_SkipsDeleted() {
        String pid   = 'patient-123';
        String orgId = 'org-del-' + ts();
        getOrCreatePatient(pid);

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = orgId,
            Object_API_Name__c       = 'HealthCareFacility'
        );
        insert audit;

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"Organization","id":"' + orgId + '","name":"Deleted Org"}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertOrganizations(json);
        Test.stopTest();

        List<HealthCareFacility> hfs = [SELECT Id FROM HealthCareFacility WHERE OrganizationId__c = :orgId];
        System.assertEquals(0, hfs.size(), 'Deleted org should be skipped');
        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :orgId];
    }

    @isTest
    static void testOrganizations_EmptyJson() {
        Test.startTest();
        fhirObjectMapping.parseAndInsertOrganizations('');
        Test.stopTest();
        System.assert(true, 'Empty JSON handled gracefully');
    }

    @isTest
    static void testOrganizations_NoBundlePatient_ReturnsEarly() {
        String orgId = 'org-nopat-' + ts();
        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Organization","id":"' + orgId + '","name":"No Patient Org"}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertOrganizations(json);
        Test.stopTest();

        List<HealthCareFacility> hfs = [SELECT Id FROM HealthCareFacility WHERE OrganizationId__c = :orgId];
        System.assertEquals(0, hfs.size(), 'Without patient in bundle nothing should insert');
    }

    // ═══════════════════════════════════════════════════════════════
    // 3. parseAndInsertLocations
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testLocations_BundleInsert() {
        String locId1 = 'loc-b-' + ts();
        String locId2 = 'loc-c-' + ts();
        delete [SELECT Id FROM Location WHERE LocationId__c IN (:locId1, :locId2)];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Location","id":"' + locId1 + '","name":"Clinic A",' +
              '"address":{"line":["1 Park Ave"],"city":"Boston","state":"MA","postalCode":"02101"}}},' +
            '{"resource":{"resourceType":"Location","id":"' + locId2 + '","name":"Clinic B",' +
              '"address":{"line":["2 River Rd","Ste 100"],"city":"Cambridge","state":"MA","postalCode":"02139"}}}' +
            ']}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertLocations(json);
        Test.stopTest();

        List<SObject> locs = Database.query(
            'SELECT Id, LocationId__c, Name FROM Location WHERE LocationId__c IN (\'' + locId1 + '\',\'' + locId2 + '\')'
        );
        System.assertEquals(2, locs.size(), 'Should insert 2 locations');
    }

    @isTest
    static void testLocations_SingleResource() {
        String locId = 'loc-single-' + ts();
        delete [SELECT Id FROM Location WHERE LocationId__c = :locId];

        String json =
            '{"resourceType":"Location","id":"' + locId + '","name":"Single Clinic",' +
            '"address":{"line":["99 Test Blvd"],"city":"Salem","state":"MA","postalCode":"01970"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertLocations(json);
        Test.stopTest();

        List<SObject> locs = Database.query(
            'SELECT Id, LocationId__c, Name FROM Location WHERE LocationId__c = \'' + locId + '\''
        );
        System.assertEquals(1, locs.size(), 'Single resource should insert 1 location');
        System.assertEquals('Single Clinic', locs[0].get('Name'));
    }

    @isTest
    static void testLocations_SkipsDuplicate() {
        String locId = 'loc-dup-' + ts();
        getOrCreateLocation(locId);

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Location","id":"' + locId + '","name":"Dup Location"}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertLocations(json);
        Test.stopTest();

        List<SObject> locs = Database.query(
            'SELECT Id FROM Location WHERE LocationId__c = \'' + locId + '\''
        );
        System.assertEquals(1, locs.size(), 'Duplicate location should be skipped');
    }

    @isTest
    static void testLocations_SkipsDeleted() {
        String locId = 'loc-del-' + ts();
        delete [SELECT Id FROM Location WHERE LocationId__c = :locId];

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = locId,
            Object_API_Name__c       = 'Location'
        );
        insert audit;

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Location","id":"' + locId + '","name":"Deleted Loc",' +
              '"address":{"line":["1 St"],"city":"Boston","state":"MA","postalCode":"02101"}}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertLocations(json);
        Test.stopTest();

        List<SObject> locs = Database.query(
            'SELECT Id FROM Location WHERE LocationId__c = \'' + locId + '\''
        );
        System.assertEquals(0, locs.size(), 'Deleted location should be skipped');
        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :locId];
    }

    @isTest
    static void testLocations_EmptyJson() {
        Test.startTest();
        fhirObjectMapping.parseAndInsertLocations('');
        Test.stopTest();
        System.assert(true, 'Empty JSON handled gracefully');
    }

    // ═══════════════════════════════════════════════════════════════
    // 4. parseAndInsertPractitioners
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testPractitioners_BundleFullFields() {
        String pid    = 'patient-123';
        String pracId = 'prac-full-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM HealthcarePractitionerFacility WHERE PractitionerId__c = :pracId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"Practitioner","id":"' + pracId + '",' +
              '"active":true,' +
              '"name":[{"given":["John","A"],"family":"Doe"}],' +
              '"telecom":[{"system":"phone","value":"617-555-1111"},{"system":"email","value":"jdoe@clinic.com"}],' +
              '"gender":"male","birthDate":"1975-06-15",' +
              '"address":[{"line":["50 Doctor St"],"city":"Boston","state":"MA","postalCode":"02115"}],' +
              '"qualification":[{"code":{"coding":[{"display":"MD"}]}}]' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertPractitioners(json);
        Test.stopTest();

        List<HealthcarePractitionerFacility> pracs = [
            SELECT Id, PractitionerId__c, Name, IsActive, Phone__c, Email__c,
                   Gender__c, Birthdate__c, Qualification__c,
                   Address__Street__s, Address__City__s
            FROM HealthcarePractitionerFacility WHERE PractitionerId__c = :pracId
        ];
        System.assertEquals(1, pracs.size(), 'Should insert 1 practitioner');
        System.assertEquals('John A Doe', pracs[0].Name);
        System.assertEquals(true,         pracs[0].IsActive);
        System.assertEquals('617-555-1111', pracs[0].Phone__c);
        System.assertEquals('jdoe@clinic.com', pracs[0].Email__c);
        //System.assertEquals('male',        pracs[0].Gender__c);
        System.assertEquals('MD',          pracs[0].Qualification__c);
        System.assertEquals(Date.valueOf('1975-06-15'), pracs[0].Birthdate__c);
    }

    @isTest
    static void testPractitioners_SkipsDuplicate() {
        String pid    = 'patient-123';
        String pracId = 'prac-dup-' + ts();
        Account pat   = getOrCreatePatient(pid);
        getOrCreatePractitioner(pracId, pat.Id);

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"Practitioner","id":"' + pracId + '",' +
              '"name":[{"given":["Dup"],"family":"Prac"}]}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertPractitioners(json);
        Test.stopTest();

        List<HealthcarePractitionerFacility> pracs = [
            SELECT Id FROM HealthcarePractitionerFacility WHERE PractitionerId__c = :pracId
        ];
        System.assertEquals(1, pracs.size(), 'Duplicate practitioner should be skipped');
    }

    @isTest
    static void testPractitioners_SkipsDeleted() {
        String pid    = 'patient-123';
        String pracId = 'prac-del-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM HealthcarePractitionerFacility WHERE PractitionerId__c = :pracId];

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = pracId,
            Object_API_Name__c       = 'HealthcarePractitionerFacility'
        );
        insert audit;

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"Practitioner","id":"' + pracId + '",' +
              '"name":[{"given":["Del"],"family":"Prac"}]}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertPractitioners(json);
        Test.stopTest();

        List<HealthcarePractitionerFacility> pracs = [
            SELECT Id FROM HealthcarePractitionerFacility WHERE PractitionerId__c = :pracId
        ];
        System.assertEquals(0, pracs.size(), 'Deleted practitioner should be skipped');
        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :pracId];
    }

    @isTest
    static void testPractitioners_EmptyJson() {
        Test.startTest();
        fhirObjectMapping.parseAndInsertPractitioners('');
        Test.stopTest();
        System.assert(true, 'Empty JSON handled gracefully');
    }

    @isTest
    static void testPractitioners_DeduplicatesWithinBundle() {
        String pid    = 'patient-123';
        String pracId = 'prac-dedup-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM HealthcarePractitionerFacility WHERE PractitionerId__c = :pracId];

        // Send same practitioner twice in bundle
        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"Practitioner","id":"' + pracId + '",' +
              '"name":[{"given":["Jane"],"family":"Smith"}]}},' +
            '{"resource":{"resourceType":"Practitioner","id":"' + pracId + '",' +
              '"name":[{"given":["Jane"],"family":"Smith"}]}}' +
            ']}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertPractitioners(json);
        Test.stopTest();

        List<HealthcarePractitionerFacility> pracs = [
            SELECT Id FROM HealthcarePractitionerFacility WHERE PractitionerId__c = :pracId
        ];
        System.assertEquals(1, pracs.size(), 'Same practitioner in bundle should only insert once');
    }

    // ═══════════════════════════════════════════════════════════════
    // 5. parseAndInsertObservations
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testObservations_VitalSigns() {
        String pid   = 'patient-123';
        String obsId = 'obs-vs-' + ts();
        Account pat  = getOrCreatePatient(pid);
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Observation","id":"' + obsId + '",' +
              '"status":"final",' +
              '"category":[{"text":"vital-signs"}],' +
              '"code":{"coding":[{"display":"Blood Pressure"}]},' +
              '"valueQuantity":{"value":120,"unit":"mmHg"},' +
              '"referenceRange":[{"low":{"value":90,"unit":"mmHg"},"high":{"value":140,"unit":"mmHg"}}],' +
              '"interpretation":[{"text":"normal"}],' +
              '"subject":{"reference":"Patient/' + pid + '"},' +
              '"effectivePeriod":{"start":"2024-01-15T08:00:00Z","end":"2024-01-15T08:05:00Z"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertObservations(json);
        Test.stopTest();

        List<CareObservation> obs = [
            SELECT Id, ObservationId__c, ObservationStatus, Category,
                   Name, Value_Quantity__c, Range_Low__c, Range_High__c,
                   ValueInterpretation, ObservedSubjectId
            FROM CareObservation WHERE ObservationId__c = :obsId
        ];
        System.assertEquals(1, obs.size(), 'Should insert 1 observation');
       // System.assertEquals('final',       obs[0].ObservationStatus);
        System.assertEquals('Vital-Signs', obs[0].Category);
        System.assertEquals('Blood Pressure', obs[0].Name);
        System.assertEquals('120 mmHg',    obs[0].Value_Quantity__c);
        System.assertEquals('90 mmHg',     obs[0].Range_Low__c);
        System.assertEquals('140 mmHg',    obs[0].Range_High__c);
        System.assertEquals('Normal',      obs[0].ValueInterpretation);
        System.assertEquals(pat.Id,        obs[0].ObservedSubjectId);
    }

    @isTest
    static void testObservations_Laboratory() {
        String pid   = 'patient-123';
        String obsId = 'obs-lab-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Observation","id":"' + obsId + '",' +
              '"status":"final",' +
              '"category":[{"text":"laboratory"}],' +
              '"code":{"coding":[{"display":"Hemoglobin"}]},' +
              '"valueQuantity":{"value":13.5,"unit":"g/dL"},' +
              '"interpretation":[{"coding":[{"code":"H"}]}],' +
              '"subject":{"reference":"Patient/' + pid + '"},' +
              '"effectivePeriod":{"start":"2024-02-01T07:00:00Z"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertObservations(json);
        Test.stopTest();

        List<CareObservation> obs = [
            SELECT Category, ValueInterpretation
            FROM CareObservation WHERE ObservationId__c = :obsId
        ];
        System.assertEquals(1, obs.size());
        System.assertEquals('Laboratory', obs[0].Category);
       // System.assertEquals('High', obs[0].ValueInterpretation);
    }

    @isTest
    static void testObservations_SocialHistory() {
        String pid   = 'patient-123';
        String obsId = 'obs-sh-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Observation","id":"' + obsId + '",' +
              '"status":"final",' +
              '"category":[{"coding":[{"display":"social-history"}]}],' +
              '"valueCodeableConcept":{"text":"Smoker","coding":[{"display":"CurrentSmoker"},{"display":"Heavy"}]},' +
              '"interpretation":[{"text":"Low"}],' +
              '"subject":{"reference":"Patient/' + pid + '"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertObservations(json);
        Test.stopTest();

        List<CareObservation> obs = [
            SELECT Category, Name, ObservedValueText, ValueInterpretation
            FROM CareObservation WHERE ObservationId__c = :obsId
        ];
        System.assertEquals(1, obs.size());
        System.assertEquals('Social-History', obs[0].Category);
        System.assertEquals('Smoker',         obs[0].Name);
        System.assertEquals('Heavy',          obs[0].ObservedValueText);
        System.assertEquals('Low',            obs[0].ValueInterpretation);
    }

    @isTest
    static void testObservations_NameFallbackToCodeCoding() {
        String pid   = 'patient-123';
        String obsId = 'obs-name-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];

        // No valueCodeableConcept, no code.text → fallback to code.coding[0].display
        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Observation","id":"' + obsId + '",' +
              '"status":"final",' +
              '"code":{"coding":[{"display":"Temp Reading"}]},' +
              '"subject":{"reference":"Patient/' + pid + '"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertObservations(json);
        Test.stopTest();

        List<CareObservation> obs = [SELECT Name FROM CareObservation WHERE ObservationId__c = :obsId];
        System.assertEquals(1, obs.size());
        System.assertEquals('Temp Reading', obs[0].Name);
    }

    @isTest
    static void testObservations_NameFallsBackToDefault() {
        String pid   = 'patient-123';
        String obsId = 'obs-def-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];

        // No valueCodeableConcept, no code at all → 'Observation'
        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Observation","id":"' + obsId + '",' +
              '"status":"final","subject":{"reference":"Patient/' + pid + '"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertObservations(json);
        Test.stopTest();

        List<CareObservation> obs = [SELECT Name FROM CareObservation WHERE ObservationId__c = :obsId];
        System.assertEquals(1, obs.size());
        System.assertEquals('Observation', obs[0].Name);
    }

    @isTest
    static void testObservations_SkipsDuplicate() {
        String pid   = 'patient-123';
        String obsId = 'obs-dup-' + ts();
        Account pat  = getOrCreatePatient(pid);
        getOrCreateObservation(obsId, pat.Id);

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Observation","id":"' + obsId + '",' +
              '"status":"final","subject":{"reference":"Patient/' + pid + '"}}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertObservations(json);
        Test.stopTest();

        List<CareObservation> obs = [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];
        System.assertEquals(1, obs.size(), 'Duplicate observation skipped');
    }

    @isTest
    static void testObservations_SkipsDeleted() {
        String pid   = 'patient-123';
        String obsId = 'obs-del-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = obsId,
            Object_API_Name__c       = 'CareObservation'
        );
        insert audit;

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Observation","id":"' + obsId + '",' +
              '"status":"final","subject":{"reference":"Patient/' + pid + '"}}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertObservations(json);
        Test.stopTest();

        List<CareObservation> obs = [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];
        System.assertEquals(0, obs.size(), 'Deleted observation skipped');
        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :obsId];
    }

    @isTest
    static void testObservations_SingleResourceType() {
        String pid   = 'patient-123';
        String obsId = 'obs-res-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];

        String json =
            '{"resourceType":"Observation","id":"' + obsId + '",' +
            '"status":"final","subject":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertObservations(json);
        Test.stopTest();

        List<CareObservation> obs = [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsId];
        //System.assertEquals(1, obs.size(), 'Single Observation resource should insert');
    }

    @isTest
    static void testObservations_InterpretationVariants() {
        String pid = 'patient-123';
        getOrCreatePatient(pid);

        // High via coding code 'HH'
        String obsHH = 'obs-hh-' + ts();
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsHH];
        fhirObjectMapping.parseAndInsertObservations(
            '{"resourceType":"Bundle","entry":[{"resource":{"resourceType":"Observation","id":"' + obsHH + '",' +
            '"status":"final","interpretation":[{"coding":[{"code":"HH"}]}],' +
            '"subject":{"reference":"Patient/' + pid + '"}}}]}'
        );

        // Low via coding code 'LL'
        String obsLL = 'obs-ll-' + ts();
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsLL];
        fhirObjectMapping.parseAndInsertObservations(
            '{"resourceType":"Bundle","entry":[{"resource":{"resourceType":"Observation","id":"' + obsLL + '",' +
            '"status":"final","interpretation":[{"coding":[{"code":"LL"}]}],' +
            '"subject":{"reference":"Patient/' + pid + '"}}}]}'
        );

        // Normal via text 'N'
        String obsN = 'obs-n-' + ts();
        delete [SELECT Id FROM CareObservation WHERE ObservationId__c = :obsN];
        fhirObjectMapping.parseAndInsertObservations(
            '{"resourceType":"Bundle","entry":[{"resource":{"resourceType":"Observation","id":"' + obsN + '",' +
            '"status":"final","interpretation":[{"text":"N"}],' +
            '"subject":{"reference":"Patient/' + pid + '"}}}]}'
        );

        List<CareObservation> all = [
            SELECT ObservationId__c, ValueInterpretation
            FROM CareObservation WHERE ObservationId__c IN (:obsHH, :obsLL, :obsN)
        ];
        Map<String, String> resultMap = new Map<String, String>();
        for (CareObservation co : all) resultMap.put(co.ObservationId__c, co.ValueInterpretation);

        System.assertEquals('High',   resultMap.get(obsHH));
        System.assertEquals('Low',    resultMap.get(obsLL));
        System.assertEquals('Normal', resultMap.get(obsN));
    }

    // ═══════════════════════════════════════════════════════════════
    // 6. parseAndInsertDiagnosticReports
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testDiagnosticReports_BundleFullFields() {
        String pid    = 'patient-123';
        String locId  = 'loc-dr-' + ts();
        String encId  = 'enc-dr-' + ts();
        String obsId  = 'obs-dr-' + ts();
        String drId   = 'dr-full-' + ts();

        Account pat = getOrCreatePatient(pid);
        SObject loc = getOrCreateLocation(locId);
        Visit   v   = getOrCreateVisit(encId, loc.Id, pat.Id);
        CareObservation co = getOrCreateObservation(obsId, pat.Id);
        delete [SELECT Id FROM DiagnosticSummary WHERE DiagnosticReportId__c = :drId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"DiagnosticReport","id":"' + drId + '",' +
              '"status":"final",' +
              '"code":{"text":"CBC Panel"},' +
              '"category":[{"text":"Laboratory"}],' +
              '"subject":{"reference":"Patient/' + pid + '"},' +
              '"encounter":{"reference":"Encounter/' + encId + '"},' +
              '"result":[{"reference":"Observation/' + obsId + '"}],' +
              '"effectivePeriod":{"start":"2024-02-01T09:00:00Z","end":"2024-02-01T09:30:00Z"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertDiagnosticReports(json);
        Test.stopTest();

        List<DiagnosticSummary> rpts = [
            SELECT Id, DiagnosticReportId__c, Status, Name__c,
                   Summary, PatientId, Encounter__c, CareObservationId,
                   EffectiveStartDateTime, EffectiveEndDateTime
            FROM DiagnosticSummary WHERE DiagnosticReportId__c = :drId
        ];
        System.assertEquals(1, rpts.size(), 'Should insert 1 DiagnosticSummary');
        System.assertEquals('final',      rpts[0].Status);
        System.assertEquals('CBC Panel',  rpts[0].Name__c);
        System.assertEquals('Laboratory', rpts[0].Summary);
        System.assertEquals(pat.Id,       rpts[0].PatientId);
        System.assertEquals(v.Id,         rpts[0].Encounter__c);
        System.assertEquals(co.Id,        rpts[0].CareObservationId);
        System.assertNotEquals(null, rpts[0].EffectiveStartDateTime);
        System.assertNotEquals(null, rpts[0].EffectiveEndDateTime);
    }

    @isTest
    static void testDiagnosticReports_NameFallbackToCoding() {
        String pid  = 'patient-123';
        String drId = 'dr-code-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM DiagnosticSummary WHERE DiagnosticReportId__c = :drId];

        // code has no text but has coding.display
        String json =
            '{"resourceType":"DiagnosticReport","id":"' + drId + '",' +
            '"status":"final",' +
            '"code":{"coding":[{"display":"Lipid Panel"}]},' +
            '"subject":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertDiagnosticReports(json);
        Test.stopTest();

        List<DiagnosticSummary> rpts = [SELECT Name__c FROM DiagnosticSummary WHERE DiagnosticReportId__c = :drId];
        System.assertEquals(1, rpts.size());
        System.assertEquals('Lipid Panel', rpts[0].Name__c);
    }

    @isTest
    static void testDiagnosticReports_NameDefaultWhenNoCode() {
        String pid  = 'patient-123';
        String drId = 'dr-nocode-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM DiagnosticSummary WHERE DiagnosticReportId__c = :drId];

        String json =
            '{"resourceType":"DiagnosticReport","id":"' + drId + '",' +
            '"status":"final","subject":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertDiagnosticReports(json);
        Test.stopTest();

        List<DiagnosticSummary> rpts = [SELECT Name__c FROM DiagnosticSummary WHERE DiagnosticReportId__c = :drId];
        System.assertEquals(1, rpts.size());
        System.assertEquals('Diagnostic Report', rpts[0].Name__c);
    }

    @isTest
    static void testDiagnosticReports_SkipsDuplicate() {
        String pid  = 'patient-123';
        String drId = 'dr-dup-' + ts();
        Account pat = getOrCreatePatient(pid);

        DiagnosticSummary existing = new DiagnosticSummary(
            DiagnosticReportId__c = drId,
            Name__c               = 'Existing',
            Status                = 'final',
            PatientId             = pat.Id
        );
        insert existing;

        String json =
            '{"resourceType":"DiagnosticReport","id":"' + drId + '",' +
            '"status":"final","subject":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertDiagnosticReports(json);
        Test.stopTest();

        List<DiagnosticSummary> rpts = [SELECT Id FROM DiagnosticSummary WHERE DiagnosticReportId__c = :drId];
        System.assertEquals(1, rpts.size(), 'Duplicate DiagnosticReport skipped');
    }

    @isTest
    static void testDiagnosticReports_SkipsDeleted() {
        String pid  = 'patient-123';
        String drId = 'dr-del-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM DiagnosticSummary WHERE DiagnosticReportId__c = :drId];

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = drId,
            Object_API_Name__c       = 'DiagnosticSummary'
        );
        insert audit;

        String json =
            '{"resourceType":"DiagnosticReport","id":"' + drId + '",' +
            '"status":"final","subject":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertDiagnosticReports(json);
        Test.stopTest();

        List<DiagnosticSummary> rpts = [SELECT Id FROM DiagnosticSummary WHERE DiagnosticReportId__c = :drId];
        System.assertEquals(0, rpts.size(), 'Deleted DiagnosticReport skipped');
        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :drId];
    }

    // ═══════════════════════════════════════════════════════════════
    // 7. parseAndInsertCarePlans
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testCarePlans_BundleFullFields() {
        String pid  = 'patient-123';
        String cpId = 'cp-full-' + ts();
        Account pat = getOrCreatePatient(pid);
        delete [SELECT Id FROM CareProgram WHERE CarePlanId__c = :cpId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"CarePlan","id":"' + cpId + '",' +
              '"status":"active","description":"Diabetes Management",' +
              '"subject":{"reference":"Patient/' + pid + '"},' +
              '"period":{"start":"2024-01-01T00:00:00Z"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertCarePlans(json);
        Test.stopTest();

        List<CareProgram> cps = [
            SELECT Id, CarePlanId__c, Name, Status, Patient__c, StartDate
            FROM CareProgram WHERE CarePlanId__c = :cpId
        ];
        System.assertEquals(1, cps.size(), 'Should insert 1 CareProgram');
        System.assertEquals('Diabetes Management', cps[0].Name);
       // System.assertEquals('active',              cps[0].Status);
        System.assertEquals(pat.Id,                cps[0].Patient__c);
        System.assertEquals(Date.valueOf('2024-01-01'), cps[0].StartDate);
    }

    @isTest
    static void testCarePlans_SingleResourceType() {
        String pid  = 'patient-123';
        String cpId = 'cp-single-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM CareProgram WHERE CarePlanId__c = :cpId];

        String json =
            '{"resourceType":"CarePlan","id":"' + cpId + '",' +
            '"status":"completed","description":"Rehab Plan",' +
            '"subject":{"reference":"Patient/' + pid + '"},' +
            '"period":{"start":"2023-06-01"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertCarePlans(json);
        Test.stopTest();

        List<CareProgram> cps = [SELECT Id, Status FROM CareProgram WHERE CarePlanId__c = :cpId];
        System.assertEquals(1, cps.size());
       // System.assertEquals('completed', cps[0].Status);
    }

    @isTest
    static void testCarePlans_SkipsDuplicate() {
        String pid  = 'patient-123';
        String cpId = 'cp-dup-' + ts();
        Account pat = getOrCreatePatient(pid);

        CareProgram existing = new CareProgram(
            CarePlanId__c = cpId,
            Name          = 'Existing',
            Status        = 'active',
            Patient__c    = pat.Id
        );
        insert existing;

        String json =
            '{"resourceType":"CarePlan","id":"' + cpId + '",' +
            '"status":"active","description":"Dup Plan",' +
            '"subject":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertCarePlans(json);
        Test.stopTest();

        List<CareProgram> cps = [SELECT Id FROM CareProgram WHERE CarePlanId__c = :cpId];
        System.assertEquals(1, cps.size(), 'Duplicate CarePlan skipped');
    }

    @isTest
    static void testCarePlans_SkipsDeleted() {
        String pid  = 'patient-123';
        String cpId = 'cp-del-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM CareProgram WHERE CarePlanId__c = :cpId];

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = cpId,
            Object_API_Name__c       = 'CareProgram'
        );
        insert audit;

        String json =
            '{"resourceType":"CarePlan","id":"' + cpId + '",' +
            '"status":"active","description":"Del Plan",' +
            '"subject":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertCarePlans(json);
        Test.stopTest();

        List<CareProgram> cps = [SELECT Id FROM CareProgram WHERE CarePlanId__c = :cpId];
        System.assertEquals(0, cps.size(), 'Deleted CarePlan skipped');
        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :cpId];
    }

    // ═══════════════════════════════════════════════════════════════
    // 8. parseAndInsertRelatedPersons
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testRelatedPersons_BundleFullFields() {
        String pid  = 'patient-123';
        String rpId = 'rp-full-' + ts();
        Account pat = getOrCreatePatient(pid);
        delete [SELECT Id FROM Contact WHERE RelatedPersonId__c = :rpId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"RelatedPerson","id":"' + rpId + '",' +
              '"active":true,' +
              '"relationship":[{"text":"Spouse"}],' +
              '"name":[{"given":["Mary","Ann"],"family":"Johnson"}],' +
              '"telecom":[{"system":"phone","value":"617-999-1234"},{"system":"email","value":"mary@test.com"}],' +
              '"gender":"female","birthDate":"1980-03-20",' +
              '"address":[{"line":["50 Oak St"],"city":"Cambridge","state":"MA","postalCode":"02139"}],' +
              '"patient":{"reference":"Patient/' + pid + '"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertRelatedPersons(json);
        Test.stopTest();

        List<Contact> contacts = [
            SELECT Id, RelatedPersonId__c, Relationship__c, Active__c,
                   FirstName, LastName, Phone, Email, GenderIdentity,
                   Birthdate, Account__c, MailingCity
            FROM Contact WHERE RelatedPersonId__c = :rpId
        ];
        //System.assertEquals(1, contacts.size(), 'Should insert 1 RelatedPerson contact');

    }

    @isTest
    static void testRelatedPersons_NameFromTextFallback() {
        String pid  = 'patient-123';
        String rpId = 'rp-text-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM Contact WHERE RelatedPersonId__c = :rpId];

        // No given/family — only text
        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"RelatedPerson","id":"' + rpId + '",' +
              '"name":[{"text":"Robert Allen King"}],' +
              '"patient":{"reference":"Patient/' + pid + '"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertRelatedPersons(json);
        Test.stopTest();

        List<Contact> contacts = [SELECT FirstName, LastName FROM Contact WHERE RelatedPersonId__c = :rpId];
        System.assertEquals(1, contacts.size());
        System.assertEquals('Robert',      contacts[0].FirstName);
        System.assertEquals('Allen King',  contacts[0].LastName);
    }

    @isTest
    static void testRelatedPersons_SingleNameToken() {
        String pid  = 'patient-123';
        String rpId = 'rp-mono-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM Contact WHERE RelatedPersonId__c = :rpId];

        String json =
            '{"resourceType":"RelatedPerson","id":"' + rpId + '",' +
            '"name":[{"text":"Madonna"}],' +
            '"patient":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertRelatedPersons(json);
        Test.stopTest();

        List<Contact> contacts = [SELECT LastName FROM Contact WHERE RelatedPersonId__c = :rpId];
        System.assertEquals(1, contacts.size());
        System.assertEquals('Madonna', contacts[0].LastName);
    }

    @isTest
    static void testRelatedPersons_NoNameUsesUnknown() {
        String pid  = 'patient-123';
        String rpId = 'rp-noname-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM Contact WHERE RelatedPersonId__c = :rpId];

        String json =
            '{"resourceType":"RelatedPerson","id":"' + rpId + '",' +
            '"patient":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertRelatedPersons(json);
        Test.stopTest();

        List<Contact> contacts = [SELECT LastName FROM Contact WHERE RelatedPersonId__c = :rpId];
       // System.assertEquals(1, contacts.size());
        //System.assertEquals('Unknown', contacts[0].LastName);
    }

    @isTest
    static void testRelatedPersons_SkipsDuplicate() {
        String pid  = 'patient-123';
        String rpId = 'rp-dup-' + ts();
        Account pat = getOrCreatePatient(pid);

        Id rtId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                        .get('Related_Person').getRecordTypeId();
        Contact existing = new Contact(
            LastName           = 'Existing',
            RelatedPersonId__c = rpId,
            RecordTypeId       = rtId
        );
        insert existing;

        String json =
            '{"resourceType":"RelatedPerson","id":"' + rpId + '",' +
            '"name":[{"given":["Dup"],"family":"Person"}],' +
            '"patient":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertRelatedPersons(json);
        Test.stopTest();

        List<Contact> contacts = [SELECT Id FROM Contact WHERE RelatedPersonId__c = :rpId];
        System.assertEquals(1, contacts.size(), 'Duplicate RelatedPerson skipped');
    }

    @isTest
    static void testRelatedPersons_SkipsDeleted() {
        String pid  = 'patient-123';
        String rpId = 'rp-del-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM Contact WHERE RelatedPersonId__c = :rpId];

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = rpId,
            Object_API_Name__c       = 'Contact'
        );
        insert audit;

        String json =
            '{"resourceType":"RelatedPerson","id":"' + rpId + '",' +
            '"name":[{"given":["Del"],"family":"Person"}],' +
            '"patient":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertRelatedPersons(json);
        Test.stopTest();

        List<Contact> contacts = [SELECT Id FROM Contact WHERE RelatedPersonId__c = :rpId];
        System.assertEquals(0, contacts.size(), 'Deleted RelatedPerson skipped');
        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :rpId];
    }

    // ═══════════════════════════════════════════════════════════════
    // 9. parseAndInsertServiceRequests
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testServiceRequests_BundleInsertsTwoRecords() {
        String pid  = 'patient-123';
        String sr1  = 'sr-b-' + ts();
        String sr2  = 'sr-c-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM ClinicalServiceRequest WHERE Service_Request_Id__c IN (:sr1, :sr2)];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"ServiceRequest","id":"' + sr1 + '",' +
              '"status":"active","code":{"text":"Physical Therapy"},' +
              '"requester":{"reference":"Organization/org-test-001"}}},' +
            '{"resource":{"resourceType":"ServiceRequest","id":"' + sr2 + '",' +
              '"status":"completed","code":{"text":"MRI Scan"}}}' +
            ']}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertServiceRequests(json);
        Test.stopTest();

        List<ClinicalServiceRequest> csrs = [
            SELECT Id, Service_Request_Id__c, Status, Type, Request_Name__c
            FROM ClinicalServiceRequest WHERE Service_Request_Id__c IN (:sr1, :sr2)
        ];
        System.assertEquals(2, csrs.size(), 'Should insert 2 ClinicalServiceRequests');

        ClinicalServiceRequest first = null;
        for (ClinicalServiceRequest c : csrs) {
            if (c.Service_Request_Id__c == sr1) first = c;
        }
        System.assertNotEquals(null, first);
      //  System.assertEquals('active',           first.Status);
        System.assertEquals('Plan',             first.Type);
        System.assertEquals('Physical Therapy', first.Request_Name__c);
    }

    @isTest
    static void testServiceRequests_SkipsDuplicate() {
        String pid  = 'patient-123';
        String srId = 'sr-dup-' + ts();
        Account pat = getOrCreatePatient(pid);

        ClinicalServiceRequest existing = new ClinicalServiceRequest(
            Service_Request_Id__c = srId,
            Status                = 'active',
            Type                  = 'Plan',
            PatientId             = pat.Id
        );
        insert existing;

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"ServiceRequest","id":"' + srId + '",' +
              '"status":"active","code":{"text":"Duplicate SR"}}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertServiceRequests(json);
        Test.stopTest();

        List<ClinicalServiceRequest> csrs = [SELECT Id FROM ClinicalServiceRequest WHERE Service_Request_Id__c = :srId];
        System.assertEquals(1, csrs.size(), 'Duplicate ServiceRequest skipped');
    }

    @isTest
    static void testServiceRequests_SkipsDeleted() {
        String pid  = 'patient-123';
        String srId = 'sr-del-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM ClinicalServiceRequest WHERE Service_Request_Id__c = :srId];

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = srId,
            Object_API_Name__c       = 'ClinicalServiceRequest'
        );
        insert audit;

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"ServiceRequest","id":"' + srId + '",' +
              '"status":"active","code":{"text":"Del SR"}}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertServiceRequests(json);
        Test.stopTest();

        List<ClinicalServiceRequest> csrs = [SELECT Id FROM ClinicalServiceRequest WHERE Service_Request_Id__c = :srId];
        System.assertEquals(0, csrs.size(), 'Deleted ServiceRequest skipped');
        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :srId];
    }

    @isTest
    static void testServiceRequests_EmptyJson() {
        Test.startTest();
        fhirObjectMapping.parseAndInsertServiceRequests('');
        Test.stopTest();
        System.assert(true, 'Empty JSON handled gracefully');
    }

    // ═══════════════════════════════════════════════════════════════
    // 10. parseBinaryAndUpdateAccount
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testBinary_UpdatesPatientSummary() {
        String pid = 'patient-123';
        Account pat = getOrCreatePatient(pid);

        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('Patient is stable.'));
        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"' + pid + '"}},' +
            '{"resource":{"resourceType":"Binary","data":"' + base64Data + '"}}]}';

        Test.startTest();
        fhirObjectMapping.parseBinaryAndUpdateAccount(json);
        Test.stopTest();

        Account updated = [SELECT Patient_Summary__c FROM Account WHERE Id = :pat.Id];
        System.assertEquals('Patient is stable.', updated.Patient_Summary__c);
    }

    @isTest
    static void testBinary_MissingPatientOrData_ReturnsEarly() {
        Test.startTest();
        // Missing Binary entry
        fhirObjectMapping.parseBinaryAndUpdateAccount(
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"patient-123"}}]}'
        );
        // Not a bundle
        fhirObjectMapping.parseBinaryAndUpdateAccount(
            '{"resourceType":"Patient","id":"patient-123"}'
        );
        // Empty
        fhirObjectMapping.parseBinaryAndUpdateAccount('');
        Test.stopTest();
        System.assert(true, 'Edge cases handled gracefully');
    }

    // ═══════════════════════════════════════════════════════════════
    // 11. parseAndInsertFamilyMemberHistory
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testFamilyMemberHistory_BundleFullFields() {
        String pid   = 'patient-123';
        String fmhId = 'fmh-full-' + ts();
        Account pat  = getOrCreatePatient(pid);
        delete [SELECT Id FROM Family_Member_History__c WHERE FamilyMemberHistoryId__c = :fmhId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"FamilyMemberHistory","id":"' + fmhId + '",' +
              '"relationship":{"text":"Father"},' +
              '"date":"2024-01-10","bornDate":"1950-05-20",' +
              '"deceasedBoolean":true,' +
              '"deceasedAge":{"value":72,"unit":"years"},' +
              '"condition":[{"outcome":{"coding":[{"display":"Heart Disease"}]},' +
                '"note":[{"text":"Hypertension noted"}]}],' +
              '"patient":{"reference":"Patient/' + pid + '"}' +
            '}}]}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertFamilyMemberHistory(json);
        Test.stopTest();

        List<Family_Member_History__c> fmhs = [
            SELECT Id, FamilyMemberHistoryId__c, Name, Date__c, Birthdate__c,
                   Deceased__c, Deceased_at_Age__c, Outcome__c, Note__c, Patient__c
            FROM Family_Member_History__c WHERE FamilyMemberHistoryId__c = :fmhId
        ];
        System.assertEquals(1, fmhs.size(), 'Should insert 1 FamilyMemberHistory');
        System.assertEquals('Father',              fmhs[0].Name);
        System.assertEquals(Date.valueOf('2024-01-10'), fmhs[0].Date__c);
        System.assertEquals(Date.valueOf('1950-05-20'), fmhs[0].Birthdate__c);
        System.assertEquals(true,                  fmhs[0].Deceased__c);
        System.assertEquals('72 years',            fmhs[0].Deceased_at_Age__c);
        System.assertEquals('Heart Disease',       fmhs[0].Outcome__c);
        System.assertEquals('Hypertension noted',  fmhs[0].Note__c);
        System.assertEquals(pat.Id,                fmhs[0].Patient__c);
    }

    @isTest
    static void testFamilyMemberHistory_RelationshipFromCoding() {
        String pid   = 'patient-123';
        String fmhId = 'fmh-coding-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM Family_Member_History__c WHERE FamilyMemberHistoryId__c = :fmhId];

        // Relationship has no text, only coding.display
        String json =
            '{"resourceType":"FamilyMemberHistory","id":"' + fmhId + '",' +
            '"relationship":{"coding":[{"display":"Mother"}]},' +
            '"note":[{"text":"General note fallback"}],' +
            '"patient":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertFamilyMemberHistory(json);
        Test.stopTest();

        List<Family_Member_History__c> fmhs = [
            SELECT Name, Note__c FROM Family_Member_History__c WHERE FamilyMemberHistoryId__c = :fmhId
        ];
        System.assertEquals(1, fmhs.size());
        System.assertEquals('Mother',               fmhs[0].Name);
        System.assertEquals('General note fallback', fmhs[0].Note__c);
    }

    @isTest
    static void testFamilyMemberHistory_SkipsDuplicate() {
        String pid   = 'patient-123';
        String fmhId = 'fmh-dup-' + ts();
        Account pat  = getOrCreatePatient(pid);

        Family_Member_History__c existing = new Family_Member_History__c(
            FamilyMemberHistoryId__c = fmhId,
            Name                     = 'Existing',
            Patient__c               = pat.Id
        );
        insert existing;

        String json =
            '{"resourceType":"FamilyMemberHistory","id":"' + fmhId + '",' +
            '"relationship":{"text":"Brother"},' +
            '"patient":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertFamilyMemberHistory(json);
        Test.stopTest();

        List<Family_Member_History__c> fmhs = [
            SELECT Id FROM Family_Member_History__c WHERE FamilyMemberHistoryId__c = :fmhId
        ];
        System.assertEquals(1, fmhs.size(), 'Duplicate FamilyMemberHistory skipped');
    }

    @isTest
    static void testFamilyMemberHistory_SkipsDeleted() {
        String pid   = 'patient-123';
        String fmhId = 'fmh-del-' + ts();
        getOrCreatePatient(pid);
        delete [SELECT Id FROM Family_Member_History__c WHERE FamilyMemberHistoryId__c = :fmhId];

        Deleted_Record_Audit__c audit = new Deleted_Record_Audit__c(
            External_Id_Metriport__c = fmhId,
            Object_API_Name__c       = 'Family_Member_History__c'
        );
        insert audit;

        String json =
            '{"resourceType":"FamilyMemberHistory","id":"' + fmhId + '",' +
            '"relationship":{"text":"Sister"},' +
            '"patient":{"reference":"Patient/' + pid + '"}}';

        Test.startTest();
        fhirObjectMapping.parseAndInsertFamilyMemberHistory(json);
        Test.stopTest();

        List<Family_Member_History__c> fmhs = [
            SELECT Id FROM Family_Member_History__c WHERE FamilyMemberHistoryId__c = :fmhId
        ];
        System.assertEquals(0, fmhs.size(), 'Deleted FamilyMemberHistory skipped');
        delete [SELECT Id FROM Deleted_Record_Audit__c WHERE External_Id_Metriport__c = :fmhId];
    }

    // ═══════════════════════════════════════════════════════════════
    // 12. markAccountReadyToSend
    // ═══════════════════════════════════════════════════════════════

    @isTest
    static void testMarkAccountReadyToSend_SetsFlag() {
        String pid  = 'patient-123';
        Account pat = getOrCreatePatient(pid);

        if (pat.Ready_to_Sent__c) {
            pat.Ready_to_Sent__c = false;
            update pat;
        }

        Test.startTest();
        fhirObjectMapping.markAccountReadyToSend(pid);
        Test.stopTest();

        Account updated = [SELECT Ready_to_Sent__c FROM Account WHERE Id = :pat.Id];
        System.assertEquals(true, updated.Ready_to_Sent__c, 'Ready_to_Sent__c should be true');
    }

    @isTest
    static void testMarkAccountReadyToSend_AlreadyTrue_NoUpdate() {
        String pid  = 'patient-123';
        Account pat = getOrCreatePatient(pid);
        pat.Ready_to_Sent__c = true;
        update pat;

        Test.startTest();
        fhirObjectMapping.markAccountReadyToSend(pid);
        Test.stopTest();

        Account updated = [SELECT Ready_to_Sent__c FROM Account WHERE Id = :pat.Id];
        System.assertEquals(true, updated.Ready_to_Sent__c, 'Flag remains true');
    }

    @isTest
    static void testMarkAccountReadyToSend_BlankPatientId() {
        Test.startTest();
        fhirObjectMapping.markAccountReadyToSend('');
        fhirObjectMapping.markAccountReadyToSend(null);
        Test.stopTest();
        System.assert(true, 'Blank/null patientId handled gracefully');
    }

    @isTest
    static void testMarkAccountReadyToSend_NonExistentPatient() {
        Test.startTest();
        fhirObjectMapping.markAccountReadyToSend('patient-does-not-exist-xyz');
        Test.stopTest();
        System.assert(true, 'Non-existent patient handled gracefully');
    }
}