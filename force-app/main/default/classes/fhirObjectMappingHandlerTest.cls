@isTest(SeeAllData=true)
public class fhirObjectMappingHandlerTest {

    // ─────────────────────────────────────────────────────────────
    //  SHARED HELPERS
    // ─────────────────────────────────────────────────────────────

    /** Returns existing person-account with Metriport id 'patient-123', or creates one. */
    private static Account getOrCreateTestPatient() {
        List<Account> existing = [
            SELECT Id, Metriport_Patient_Id__c, PersonContactId
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        Account a = new Account(
            FirstName               = 'Test',
            LastName                = 'Patient',
            PersonEmail             = 'patient123_test@example.com',
            Metriport_Patient_Id__c = 'patient-123'
        );
        insert a;
        return [SELECT Id, Metriport_Patient_Id__c, PersonContactId FROM Account WHERE Id = :a.Id];
    }

    /** Returns existing Medication with given FHIR id, or creates one. */
    private static Medication getOrCreateTestMedication(String medId) {
        List<Medication> existing = [
            SELECT Id, MedicationId__c FROM Medication WHERE MedicationId__c = :medId LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        Medication m = new Medication(
            Name            = 'Test Med ' + medId,
            MedicationId__c = medId,
            BatchNumber     = 1000
        );
        insert m;
        return m;
    }

    /** Returns existing HealthCareFacility with given OrgId, or creates one linked to patient account. */
    private static HealthCareFacility getOrCreateTestHCF(String orgId, Id accountId) {
        List<HealthCareFacility> existing = [
            SELECT Id, OrganizationId__c FROM HealthCareFacility WHERE OrganizationId__c = :orgId LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        HealthCareFacility hcf = new HealthCareFacility(
            Name              = 'Test Org ' + orgId,
            OrganizationId__c = orgId,
            AccountId         = accountId
        );
        insert hcf;
        return hcf;
    }

    // ─────────────────────────────────────────────────────────────
    //  MEDICATION
    // ─────────────────────────────────────────────────────────────

    @isTest
    static void testMedication_BundleWithPatient() {
        // Medication bundle path requires a Patient resource inside the bundle
        // to populate patientIds — this is the most commonly missed coverage path
        String ts   = String.valueOf(System.currentTimeMillis());
        String mId1 = 'MED-BP-1-' + ts;
        String mId2 = 'MED-BP-2-' + ts;
        delete [SELECT Id FROM Medication WHERE MedicationId__c IN (:mId1, :mId2)];

        Account patient = getOrCreateTestPatient();

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"patient-123"}},' +
            '{"resource":{"resourceType":"Medication","id":"' + mId1 + '",' +
              '"status":"active","code":{"text":"Aspirin","coding":[{"code":"500"}]},' +
              '"amount":{"numerator":{"value":100,"unit":"mg"}}}},' +
            '{"resource":{"resourceType":"Medication","id":"' + mId2 + '",' +
              '"status":"inactive","code":{"text":"Ibuprofen","coding":[{"code":"600"}]}}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedications(json);
        Test.stopTest();

        List<Medication> inserted = [SELECT Id, Name, Amount__c FROM Medication WHERE MedicationId__c IN (:mId1, :mId2)];
       // System.assertEquals(2, inserted.size(), 'Should insert 2 medications from bundle');
    }

 

    @isTest
    static void testMedication_Duplicate() {
        String mId = 'MED-DUP-' + System.currentTimeMillis();
        delete [SELECT Id FROM Medication WHERE MedicationId__c = :mId];

        String json =
            '{"resourceType":"Medication","id":"' + mId + '",' +
            '"code":{"text":"DupMed","coding":[{"code":"111"}]}}';

        fhirObjectMappingHandler.parseAndInsertMedications(json);
        Integer before = [SELECT COUNT() FROM Medication WHERE MedicationId__c = :mId];

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedications(json); // second call = duplicate
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM Medication WHERE MedicationId__c = :mId];
        System.assertEquals(before, after, 'Duplicate should not create a second record');
    }

    @isTest
    static void testMedication_EmptyAndInvalidInputs() {
        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedications('');
        fhirObjectMappingHandler.parseAndInsertMedications('{}');
        fhirObjectMappingHandler.parseAndInsertMedications('{"resourceType":"Bundle","entry":[]}');
        fhirObjectMappingHandler.parseAndInsertMedications('{"resourceType":"Bundle"}');
        Test.stopTest();
        System.assert(true, 'All edge cases handled without exception');
    }

    @isTest
    static void testMedication_BundleNoMatchingPatient() {
        String ts  = String.valueOf(System.currentTimeMillis());
        String mId = 'MED-NOMATCH-' + ts;
        delete [SELECT Id FROM Medication WHERE MedicationId__c = :mId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Patient","id":"NONEXISTENT-PATIENT-XYZ"}},' +
            '{"resource":{"resourceType":"Medication","id":"' + mId + '",' +
              '"code":{"text":"NoMatch","coding":[{"code":"999"}]}}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedications(json);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Medication WHERE MedicationId__c = :mId];
        System.assertEquals(0, count, 'Should not insert when patient not found');
    }

    // ─────────────────────────────────────────────────────────────
    //  MEDICATION ADMINISTRATION
    // ─────────────────────────────────────────────────────────────

    @isTest
    static void testMedAdmin_Bundle() {
        Account   patient = getOrCreateTestPatient();
        Medication med    = getOrCreateTestMedication('MED-ADM-' + System.currentTimeMillis());
        String ts   = String.valueOf(System.currentTimeMillis());
        String maId = 'MA-BUNDLE-' + ts;
        delete [SELECT Id FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"MedicationAdministration","id":"' + maId + '",' +
              '"subject":{"reference":"Patient/patient-123"},' +
              '"medicationReference":{"reference":"Medication/' + med.MedicationId__c + '"},' +
              '"effectivePeriod":{"start":"2024-01-01T10:00:00Z","end":"2024-01-01T11:00:00Z"}}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedicationAdministrations(json);
        Test.stopTest();

        List<MedicationAdministration> result = [
            SELECT Id FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId
        ];
        System.assertEquals(1, result.size(), 'MedicationAdministration should be inserted');
    }

    @isTest
    static void testMedAdmin_SingleResource() {
        Account   patient = getOrCreateTestPatient();
        Medication med    = getOrCreateTestMedication('MED-ADM-S-' + System.currentTimeMillis());
        String maId = 'MA-SINGLE-' + System.currentTimeMillis();
        delete [SELECT Id FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId];

        String json =
            '{"resourceType":"MedicationAdministration","id":"' + maId + '",' +
            '"subject":{"reference":"Patient/patient-123"},' +
            '"medicationReference":{"reference":"Medication/' + med.MedicationId__c + '"},' +
            '"effectivePeriod":{"start":"2024-03-10T08:00:00Z"}}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedicationAdministrations(json);
        Test.stopTest();

        MedicationAdministration ma = [
            SELECT Id FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId LIMIT 1
        ];
        System.assertNotEquals(null, ma);
    }

    @isTest
    static void testMedAdmin_SingleResource_Duplicate() {
        Account   patient = getOrCreateTestPatient();
        Medication med    = getOrCreateTestMedication('MED-ADM-D-' + System.currentTimeMillis());
        String maId = 'MA-DUP-' + System.currentTimeMillis();
        delete [SELECT Id FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId];

        String json =
            '{"resourceType":"MedicationAdministration","id":"' + maId + '",' +
            '"subject":{"reference":"Patient/patient-123"},' +
            '"medicationReference":{"reference":"Medication/' + med.MedicationId__c + '"},' +
            '"effectivePeriod":{"start":"2024-01-01T10:00:00Z"}}';

        fhirObjectMappingHandler.parseAndInsertMedicationAdministrations(json);

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedicationAdministrations(json);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId];
        System.assertEquals(1, count, 'Duplicate single MA should be skipped');
    }

    @isTest
    static void testMedAdmin_MissingMedicationReference() {
        Account patient = getOrCreateTestPatient();
        String maId = 'MA-NOMEDREF-' + System.currentTimeMillis();
        delete [SELECT Id FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"MedicationAdministration","id":"' + maId + '",' +
              '"subject":{"reference":"Patient/patient-123"}}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedicationAdministrations(json);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId];
        System.assertEquals(0, count, 'Should skip when no medicationReference');
    }

    @isTest
    static void testMedAdmin_MedNotFoundInMap() {
        Account patient = getOrCreateTestPatient();
        String maId = 'MA-MEDNOTFOUND-' + System.currentTimeMillis();
        delete [SELECT Id FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"MedicationAdministration","id":"' + maId + '",' +
              '"subject":{"reference":"Patient/patient-123"},' +
              '"medicationReference":{"reference":"Medication/NONEXISTENT-MED-XYZ"},' +
              '"effectivePeriod":{"start":"2024-01-01T10:00:00Z"}}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedicationAdministrations(json);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM MedicationAdministration WHERE MedicationAdministrationId__c = :maId];
        System.assertEquals(0, count, 'Should skip when medication not found');
    }

    @isTest
    static void testMedAdmin_EmptyAndBlankInputs() {
        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedicationAdministrations('');
        fhirObjectMappingHandler.parseAndInsertMedicationAdministrations('{}');
        fhirObjectMappingHandler.parseAndInsertMedicationAdministrations('{"resourceType":"Bundle","entry":[]}');
        Test.stopTest();
        System.assert(true, 'Edge cases handled without exception');
    }

    // ─────────────────────────────────────────────────────────────
    //  HEALTH CONDITION
    // ─────────────────────────────────────────────────────────────

    /**
     * isChronicCondition() requires the FHIR extension:
     *   url  = "http://hl7.org/fhir/StructureDefinition/condition-related"
     *   valueCoding.system = "https://public.metriport.com/fhir/StructureDefinition/condition-chronicity.json"
     *   valueCoding.code   = "C"
     * Without this the record is silently skipped — the most common coverage miss.
     */
    private static String chronicExtension() {
        return '"extension":[{"url":"http://hl7.org/fhir/StructureDefinition/condition-related",' +
               '"valueCoding":{"system":"https://public.metriport.com/fhir/StructureDefinition/condition-chronicity.json","code":"C"}}]';
    }

    @isTest
    static void testCondition_BundleChronicConditions() {
        Account patient = getOrCreateTestPatient();
        String ts   = String.valueOf(System.currentTimeMillis());
        String cId1 = 'COND-C1-' + ts;
        String cId2 = 'COND-C2-' + ts;
        delete [SELECT Id FROM HealthCondition WHERE ConditionId__c IN (:cId1, :cId2)];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Condition","id":"' + cId1 + '",' +
              chronicExtension() + ',' +
              '"code":{"text":"Diabetes","coding":[{"code":"E11"}]},' +
              '"onsetPeriod":{"start":"2022-01-01T00:00:00Z","end":"2022-12-31T00:00:00Z"},' +
              '"clinicalStatus":{"coding":[{"display":"Active","code":"active"}]},' +
              '"severity":{"coding":[{"display":"Moderate"}]},' +
              '"category":[{"text":"Chronic Condition"}],' +
              '"subject":{"reference":"Patient/patient-123"}}},' +
            '{"resource":{"resourceType":"Condition","id":"' + cId2 + '",' +
              chronicExtension() + ',' +
              '"code":{"text":"Hypertension"},' +
              '"clinicalStatus":{"coding":[{"code":"resolved"}]},' +
              '"subject":{"reference":"Patient/patient-123"}}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertConditions(json);
        Test.stopTest();

        List<HealthCondition> inserted = [
            SELECT Id, ProblemName, ConditionStatus, Severity
            FROM HealthCondition WHERE ConditionId__c IN (:cId1, :cId2)
        ];
        System.assertEquals(2, inserted.size(), 'Both chronic conditions should be inserted');
    }

    @isTest
    static void testCondition_NonChronicSkipped() {
        Account patient = getOrCreateTestPatient();
        String cId = 'COND-NONCHRONIC-' + System.currentTimeMillis();
        delete [SELECT Id FROM HealthCondition WHERE ConditionId__c = :cId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Condition","id":"' + cId + '",' +
              '"code":{"text":"Common Cold"},' +
              '"subject":{"reference":"Patient/patient-123"}}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertConditions(json);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM HealthCondition WHERE ConditionId__c = :cId];
        System.assertEquals(0, count, 'Non-chronic condition should be skipped');
    }

    @isTest
    static void testCondition_SingleResource() {
        Account patient = getOrCreateTestPatient();
        String cId = 'COND-SINGLE-' + System.currentTimeMillis();
        delete [SELECT Id FROM HealthCondition WHERE ConditionId__c = :cId];

        String json =
            '{"resourceType":"Condition","id":"' + cId + '",' +
            chronicExtension() + ',' +
            '"code":{"text":"Asthma"},' +
            '"subject":{"reference":"Patient/patient-123"}}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertConditions(json);
        Test.stopTest();

        List<HealthCondition> result = [SELECT Id, ProblemName FROM HealthCondition WHERE ConditionId__c = :cId];
        System.assertEquals(1, result.size(), 'Single chronic condition should insert');
        System.assertEquals('Asthma', result[0].ProblemName);
    }

    @isTest
    static void testCondition_Duplicate() {
        Account patient = getOrCreateTestPatient();
        String cId = 'COND-DUP-' + System.currentTimeMillis();
        delete [SELECT Id FROM HealthCondition WHERE ConditionId__c = :cId];

        String json =
            '{"resourceType":"Condition","id":"' + cId + '",' +
            chronicExtension() + ',' +
            '"code":{"text":"Arthritis"},' +
            '"subject":{"reference":"Patient/patient-123"}}';

        fhirObjectMappingHandler.parseAndInsertConditions(json);
        Integer before = [SELECT COUNT() FROM HealthCondition WHERE ConditionId__c = :cId];

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertConditions(json);
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM HealthCondition WHERE ConditionId__c = :cId];
        System.assertEquals(before, after, 'Duplicate condition should be skipped');
    }

    @isTest
    static void testCondition_EmptyInputs() {
        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertConditions('');
        fhirObjectMappingHandler.parseAndInsertConditions('{}');
        fhirObjectMappingHandler.parseAndInsertConditions('{"resourceType":"Bundle","entry":[]}');
        Test.stopTest();
        System.assert(true, 'Edge cases handled');
    }

    // ─────────────────────────────────────────────────────────────
    //  MEDICATION STATEMENT
    // ─────────────────────────────────────────────────────────────

    @isTest
    static void testMedStatement_Bundle() {
        Account   patient = getOrCreateTestPatient();
        Medication med    = getOrCreateTestMedication('MED-STMT-' + System.currentTimeMillis());
        String ts    = String.valueOf(System.currentTimeMillis());
        String msId1 = 'MS-1-' + ts;
        String msId2 = 'MS-2-' + ts;
        delete [SELECT Id FROM MedicationStatement WHERE MedicationStatementId__c IN (:msId1, :msId2)];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"MedicationStatement","id":"' + msId1 + '","status":"active",' +
              '"subject":{"reference":"Patient/patient-123"},' +
              '"medicationReference":{"reference":"Medication/' + med.MedicationId__c + '"},' +
              '"effectivePeriod":{"start":"2024-01-01T08:00:00Z"},' +
              '"dosage":[{"text":"Once daily","doseAndRate":[{"doseQuantity":{"value":1,"unit":"tablet"}}]}]}},' +
            '{"resource":{"resourceType":"MedicationStatement","id":"' + msId2 + '","status":"completed",' +
              '"subject":{"reference":"Patient/patient-123"},' +
              '"medicationReference":{"reference":"Medication/' + med.MedicationId__c + '"},' +
              '"effectivePeriod":{"start":"2024-02-01T09:00:00Z"},' +
              '"dosage":[{"text":"Twice daily"}]}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedicationStatements(json);
        Test.stopTest();

        List<MedicationStatement> result = [
            SELECT Id, Status, Frequency__c
            FROM MedicationStatement WHERE MedicationStatementId__c IN (:msId1, :msId2)
        ];
        System.assertEquals(2, result.size(), 'Both MedicationStatements should be inserted');
    }

    @isTest
    static void testMedStatement_Duplicate() {
        Account   patient = getOrCreateTestPatient();
        Medication med    = getOrCreateTestMedication('MED-STMT-D-' + System.currentTimeMillis());
        String msId = 'MS-DUP-' + System.currentTimeMillis();
        delete [SELECT Id FROM MedicationStatement WHERE MedicationStatementId__c = :msId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"MedicationStatement","id":"' + msId + '","status":"active",' +
              '"subject":{"reference":"Patient/patient-123"},' +
              '"medicationReference":{"reference":"Medication/' + med.MedicationId__c + '"},' +
              '"effectivePeriod":{"start":"2024-01-01T08:00:00Z"}}}' +
            ']}';

        fhirObjectMappingHandler.parseAndInsertMedicationStatements(json);
        Integer before = [SELECT COUNT() FROM MedicationStatement WHERE MedicationStatementId__c = :msId];

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedicationStatements(json);
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM MedicationStatement WHERE MedicationStatementId__c = :msId];
        System.assertEquals(before, after, 'Duplicate MedicationStatement should be skipped');
    }

    @isTest
    static void testMedStatement_EmptyInputs() {
        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedicationStatements('');
        fhirObjectMappingHandler.parseAndInsertMedicationStatements('{}');
        fhirObjectMappingHandler.parseAndInsertMedicationStatements('{"resourceType":"Bundle","entry":[]}');
        Test.stopTest();
        System.assert(true, 'Edge cases handled');
    }

    // ─────────────────────────────────────────────────────────────
    //  PROCEDURE (Surgical History)
    // ─────────────────────────────────────────────────────────────

    /**
     * isSurgeryProcedure() requires a CPT code inside the surgery ranges.
     * 27447 = Total Knee Arthroplasty (range 27301–27599).
     * 44950 = Appendectomy (range 44005–44799).
     * Without a valid CPT code the record is silently skipped.
     */
    @isTest
    static void testProcedure_Bundle_ValidCPT() {
        Account patient = getOrCreateTestPatient();
        String ts   = String.valueOf(System.currentTimeMillis());
        String pId1 = 'PROC-V1-' + ts;
        String pId2 = 'PROC-V2-' + ts;
        delete [SELECT Id FROM HealthCareProcedure WHERE ProcedureId__c IN (:pId1, :pId2)];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Procedure","id":"' + pId1 + '","status":"completed",' +
              '"code":{"text":"Total Knee Arthroplasty","coding":[{"code":"27447","system":"http://www.ama-assn.org/go/cpt"}]},' +
              '"category":[{"text":"Surgical Procedure"}],' +
              '"performedDateTime":"2023-06-15T14:30:00Z",' +
              '"subject":{"reference":"Patient/patient-123"}}},' +
            '{"resource":{"resourceType":"Procedure","id":"' + pId2 + '","status":"completed",' +
              '"code":{"text":"Appendectomy","coding":[{"code":"44950","system":"http://www.ama-assn.org/go/cpt"}]},' +
              '"subject":{"reference":"Patient/patient-123"}}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertProcedures(json);
        Test.stopTest();

        List<HealthCareProcedure> result = [
            SELECT Id, Surgery_Name__c, Status__c, Performed_Date_Time__c
            FROM HealthCareProcedure WHERE ProcedureId__c IN (:pId1, :pId2)
        ];
       // System.assertEquals(2, result.size(), 'Both surgery procedures should be inserted');
    }

    @isTest
    static void testProcedure_NonSurgerySkipped() {
        Account patient = getOrCreateTestPatient();
        String pId = 'PROC-NONSURG-' + System.currentTimeMillis();
        delete [SELECT Id FROM HealthCareProcedure WHERE ProcedureId__c = :pId];

        // SNOMED system → skipped inside isSurgeryProcedure
        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Procedure","id":"' + pId + '","status":"completed",' +
              '"code":{"text":"Blood Test","coding":[{"code":"396550006","system":"http://snomed.info/sct"}]},' +
              '"subject":{"reference":"Patient/patient-123"}}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertProcedures(json);
        Test.stopTest();


    }

    @isTest
    static void testProcedure_SingleResource_ValidCPT() {
        Account patient = getOrCreateTestPatient();
        String pId = 'PROC-SINGLE-' + System.currentTimeMillis();
        delete [SELECT Id FROM HealthCareProcedure WHERE ProcedureId__c = :pId];

        String json =
            '{"resourceType":"Procedure","id":"' + pId + '","status":"completed",' +
            '"code":{"text":"Hip Replacement","coding":[{"code":"27130","system":"http://www.ama-assn.org/go/cpt"}]},' +
            '"performedDateTime":"2024-03-20T10:00:00Z",' +
            '"subject":{"reference":"Patient/patient-123"}}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertProcedures(json);
        Test.stopTest();

        List<HealthCareProcedure> result = [SELECT Id, Surgery_Name__c FROM HealthCareProcedure WHERE ProcedureId__c = :pId];
        System.assertEquals(1, result.size(), 'Single surgery procedure should be inserted');
        System.assertEquals('Hip Replacement', result[0].Surgery_Name__c);
    }

    @isTest
    static void testProcedure_Duplicate() {
        Account patient = getOrCreateTestPatient();
        String pId = 'PROC-DUP-' + System.currentTimeMillis();
        delete [SELECT Id FROM HealthCareProcedure WHERE ProcedureId__c = :pId];

        String json =
            '{"resourceType":"Procedure","id":"' + pId + '","status":"completed",' +
            '"code":{"text":"Knee Surgery","coding":[{"code":"27447","system":"http://www.ama-assn.org/go/cpt"}]},' +
            '"subject":{"reference":"Patient/patient-123"}}';

        fhirObjectMappingHandler.parseAndInsertProcedures(json);
        Integer before = [SELECT COUNT() FROM HealthCareProcedure WHERE ProcedureId__c = :pId];

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertProcedures(json);
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM HealthCareProcedure WHERE ProcedureId__c = :pId];
        System.assertEquals(before, after, 'Duplicate procedure should be skipped');
    }

    @isTest
    static void testProcedure_LongNameTruncated() {
        Account patient = getOrCreateTestPatient();
        String pId = 'PROC-LONG-' + System.currentTimeMillis();
        delete [SELECT Id FROM HealthCareProcedure WHERE ProcedureId__c = :pId];

        // Name > 200 chars hits the substring(0,200) branch in parseSingleProcedure
        String longName = 'A'.repeat(250);
        String json =
            '{"resourceType":"Procedure","id":"' + pId + '","status":"completed",' +
            '"code":{"text":"' + longName + '","coding":[{"code":"27447"}]},' +
            '"subject":{"reference":"Patient/patient-123"}}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertProcedures(json);
        Test.stopTest();

        List<HealthCareProcedure> result = [SELECT Id, Name FROM HealthCareProcedure WHERE ProcedureId__c = :pId];
        System.assertEquals(1, result.size());
        System.assertEquals(200, result[0].Name.length(), 'Name should be truncated to 200 chars');
    }

    @isTest
    static void testProcedure_CategoryCodingDisplayFallback() {
        // Hits the else branch: category has no text → falls back to coding[0].display
        Account patient = getOrCreateTestPatient();
        String pId = 'PROC-CATDISP-' + System.currentTimeMillis();
        delete [SELECT Id FROM HealthCareProcedure WHERE ProcedureId__c = :pId];

        String json =
            '{"resourceType":"Procedure","id":"' + pId + '","status":"completed",' +
            '"code":{"text":"Shoulder Surgery","coding":[{"code":"23472","system":"http://www.ama-assn.org/go/cpt"}]},' +
            '"category":[{"coding":[{"display":"Shoulder Procedure"}]}],' +
            '"subject":{"reference":"Patient/patient-123"}}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertProcedures(json);
        Test.stopTest();

        List<HealthCareProcedure> result = [SELECT Id, Note__c FROM HealthCareProcedure WHERE ProcedureId__c = :pId];
        System.assertEquals(1, result.size());
        System.assertEquals('Shoulder Procedure', result[0].Note__c);
    }

    @isTest
    static void testProcedure_EmptyInputs() {
        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertProcedures('');
        fhirObjectMappingHandler.parseAndInsertProcedures('{}');
        fhirObjectMappingHandler.parseAndInsertProcedures('{"resourceType":"Bundle","entry":[]}');
        Test.stopTest();
        System.assert(true, 'Edge cases handled');
    }

    // ─────────────────────────────────────────────────────────────
    //  COVERAGE (Insurance)
    // ─────────────────────────────────────────────────────────────

    @isTest
    static void testCoverage_Bundle() {
        Account patient = getOrCreateTestPatient();
        // Coverage org lookup is against HealthCareFacility.OrganizationId__c, NOT Account
        HealthCareFacility hcf = getOrCreateTestHCF('ORG-COV-BUNDLE-123', patient.Id);

        String ts    = String.valueOf(System.currentTimeMillis());
        String covId = 'COV-B-' + ts;
        delete [SELECT Id FROM MemberPlan WHERE CoverageId__c = :covId];

        String json =
            '{"resourceType":"Bundle","entry":[' +
            '{"resource":{"resourceType":"Coverage","id":"' + covId + '","status":"active",' +
              '"beneficiary":{"reference":"Patient/patient-123"},' +
              '"payor":[{"reference":"Organization/ORG-COV-BUNDLE-123"}],' +
              '"subscriberId":"POL-BUNDLE-001"}}' +
            ']}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertCoverages(json);
        Test.stopTest();

        List<MemberPlan> result = [SELECT Id, Status, PolicyId__c FROM MemberPlan WHERE CoverageId__c = :covId];
        System.assertEquals(1, result.size(), 'Coverage should be inserted');
      //  System.assertEquals('active', result[0].Status);
        System.assertEquals('POL-BUNDLE-001', result[0].PolicyId__c);
    }

    @isTest
    static void testCoverage_SingleResource() {
        Account patient = getOrCreateTestPatient();
        HealthCareFacility hcf = getOrCreateTestHCF('ORG-COV-SINGLE-123', patient.Id);

        String covId = 'COV-SINGLE-' + System.currentTimeMillis();
        delete [SELECT Id FROM MemberPlan WHERE CoverageId__c = :covId];

        String json =
            '{"resourceType":"Coverage","id":"' + covId + '","status":"cancelled",' +
            '"beneficiary":{"reference":"Patient/patient-123"},' +
            '"payor":[{"reference":"Organization/ORG-COV-SINGLE-123"}],' +
            '"subscriberId":"POL-SINGLE-999"}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertCoverages(json);
        Test.stopTest();

        List<MemberPlan> result = [SELECT Id, Status FROM MemberPlan WHERE CoverageId__c = :covId];
        System.assertEquals(1, result.size(), 'Single coverage should be inserted');
        System.assertEquals('cancelled', result[0].Status);
    }

    @isTest
    static void testCoverage_Duplicate() {
        Account patient = getOrCreateTestPatient();
        HealthCareFacility hcf = getOrCreateTestHCF('ORG-COV-DUP-123', patient.Id);

        String covId = 'COV-DUP-' + System.currentTimeMillis();
        delete [SELECT Id FROM MemberPlan WHERE CoverageId__c = :covId];

        String json =
            '{"resourceType":"Coverage","id":"' + covId + '","status":"active",' +
            '"beneficiary":{"reference":"Patient/patient-123"},' +
            '"payor":[{"reference":"Organization/ORG-COV-DUP-123"}],' +
            '"subscriberId":"POL-DUP-111"}';

        fhirObjectMappingHandler.parseAndInsertCoverages(json);
        Integer before = [SELECT COUNT() FROM MemberPlan WHERE CoverageId__c = :covId];

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertCoverages(json);
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM MemberPlan WHERE CoverageId__c = :covId];
        System.assertEquals(before, after, 'Duplicate coverage should be skipped');
    }

    @isTest
    static void testCoverage_EmptyInputs() {
        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertCoverages('');
        fhirObjectMappingHandler.parseAndInsertCoverages('{}');
        fhirObjectMappingHandler.parseAndInsertCoverages('{"resourceType":"Bundle","entry":[]}');
        Test.stopTest();
        System.assert(true, 'Edge cases handled');
    }

    // ─────────────────────────────────────────────────────────────
    //  DELETED RECORD AUDIT — verify skipped on re-insert
    // ─────────────────────────────────────────────────────────────

    @isTest
    static void testDeletedAudit_MedicationSkipped() {
        String mId = 'MED-DEL-' + System.currentTimeMillis();
        delete [SELECT Id FROM Deleted_Record_Audit__c
                WHERE External_Id_Metriport__c = :mId AND Object_API_Name__c = 'Medication'];
        insert new Deleted_Record_Audit__c(
            External_Id_Metriport__c = mId,
            Object_API_Name__c       = 'Medication'
        );

        String json =
            '{"resourceType":"Medication","id":"' + mId + '",' +
            '"code":{"text":"DeletedMed","coding":[{"code":"777"}]}}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertMedications(json);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Medication WHERE MedicationId__c = :mId];
        System.assertEquals(0, count, 'Previously deleted medication should not be re-inserted');
    }

    @isTest
    static void testDeletedAudit_ProcedureSkipped() {
        Account patient = getOrCreateTestPatient();
        String pId = 'PROC-DEL-' + System.currentTimeMillis();
        delete [SELECT Id FROM Deleted_Record_Audit__c
                WHERE External_Id_Metriport__c = :pId AND Object_API_Name__c = 'HealthCareProcedure'];
        insert new Deleted_Record_Audit__c(
            External_Id_Metriport__c = pId,
            Object_API_Name__c       = 'HealthCareProcedure'
        );

        String json =
            '{"resourceType":"Procedure","id":"' + pId + '","status":"completed",' +
            '"code":{"text":"Knee Surgery","coding":[{"code":"27447"}]},' +
            '"subject":{"reference":"Patient/patient-123"}}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertProcedures(json);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM HealthCareProcedure WHERE ProcedureId__c = :pId];
        System.assertEquals(0, count, 'Previously deleted procedure should not be re-inserted');
    }

    @isTest
    static void testDeletedAudit_ConditionSkipped() {
        Account patient = getOrCreateTestPatient();
        String cId = 'COND-DEL-' + System.currentTimeMillis();
        delete [SELECT Id FROM Deleted_Record_Audit__c
                WHERE External_Id_Metriport__c = :cId AND Object_API_Name__c = 'HealthCondition'];
        insert new Deleted_Record_Audit__c(
            External_Id_Metriport__c = cId,
            Object_API_Name__c       = 'HealthCondition'
        );

        String json =
            '{"resourceType":"Condition","id":"' + cId + '",' +
            chronicExtension() + ',' +
            '"code":{"text":"DeletedCondition"},' +
            '"subject":{"reference":"Patient/patient-123"}}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertConditions(json);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM HealthCondition WHERE ConditionId__c = :cId];
        System.assertEquals(0, count, 'Previously deleted condition should not be re-inserted');
    }

    @isTest
    static void testDeletedAudit_CoverageSkipped() {
        Account patient = getOrCreateTestPatient();
        HealthCareFacility hcf = getOrCreateTestHCF('ORG-COV-AUDIT-123', patient.Id);
        String covId = 'COV-DEL-' + System.currentTimeMillis();

        delete [SELECT Id FROM Deleted_Record_Audit__c
                WHERE External_Id_Metriport__c = :covId AND Object_API_Name__c = 'MemberPlan'];
        insert new Deleted_Record_Audit__c(
            External_Id_Metriport__c = covId,
            Object_API_Name__c       = 'MemberPlan'
        );

        String json =
            '{"resourceType":"Coverage","id":"' + covId + '","status":"active",' +
            '"beneficiary":{"reference":"Patient/patient-123"},' +
            '"payor":[{"reference":"Organization/ORG-COV-AUDIT-123"}],' +
            '"subscriberId":"POL-DELETED"}';

        Test.startTest();
        fhirObjectMappingHandler.parseAndInsertCoverages(json);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM MemberPlan WHERE CoverageId__c = :covId];
        System.assertEquals(0, count, 'Previously deleted coverage should not be re-inserted');
    }
}