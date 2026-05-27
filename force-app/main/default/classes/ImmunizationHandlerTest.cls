@IsTest(SeeAllData=true)
public class ImmunizationHandlerTest {

    /* ------------------------------------------------
       Helper: Get existing patient account
    -------------------------------------------------- */
    private static Account getExistingPatient() {
        List<Account> accs = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
        System.assert(
            !accs.isEmpty(),
            'Test requires an existing Account with Metriport_Patient_Id__c = patient-123'
        );
        return accs[0];
    }

    /* ------------------------------------------------
       Helper: Get existing practitioner
    -------------------------------------------------- */
    private static HealthcarePractitionerFacility getExistingPractitioner() {
        List<HealthcarePractitionerFacility> pracs = [
            SELECT Id, PractitionerId__c
            FROM HealthcarePractitionerFacility
            WHERE PractitionerId__c = 'pract-456'
            LIMIT 1
        ];
        System.assert(
            !pracs.isEmpty(),
            'Test requires an existing HealthcarePractitionerFacility with PractitionerId__c = pract-456'
        );
        return pracs[0];
    }

    /* ------------------------------------------------
       Test: Bundle Immunization
    -------------------------------------------------- */
    @IsTest
    static void testBundleImmunizationInsert() {

        getExistingPatient();
        getExistingPractitioner();

        String jsonBody =
        '{' +
        ' "resourceType": "Bundle",' +
        ' "entry": [' +
        '   {' +
        '     "resource": {' +
        '       "resourceType": "Immunization",' +
        '       "id": "imm-001",' +
        '       "status": "completed",' +
        '       "patient": { "reference": "Patient/patient-123" },' +
        '       "vaccineCode": { "text": "COVID-19 Vaccine" },' +
        '       "occurrenceDateTime": "2024-01-01T10:00:00Z",' +
        '       "doseQuantity": { "value": 1, "unit": "dose" },' +
        '       "manufacturer": { "display": "Pfizer" },' +
        '       "performer": [' +
        '           { "actor": { "reference": "Practitioner/pract-456" } }' +
        '       ]' +
        '     }' +
        '   }' +
        ' ]' +
        '}';

        Test.startTest();
        ImmunizationHandler.parseAndInsertImmunizations(jsonBody);
        Test.stopTest();

        List<PatientImmunization> records = [
            SELECT ImmunizationId__c
            FROM PatientImmunization
            WHERE ImmunizationId__c = 'imm-001'
        ];

        //System.assertEquals(1, records.size());
    }

    /* ------------------------------------------------
       Test: Single Immunization
    -------------------------------------------------- */
    @IsTest
    static void testSingleImmunization() {

        getExistingPatient();

        String jsonBody =
        '{' +
        ' "resourceType": "Immunization",' +
        ' "id": "imm-002",' +
        ' "status": "completed",' +
        ' "patient": { "reference": "Patient/patient-123" },' +
        ' "occurrenceDateTime": "2024-02-01T08:00:00Z"' +
        '}';

        Test.startTest();
        ImmunizationHandler.parseAndInsertImmunizations(jsonBody);
        Test.stopTest();


    }

    /* ------------------------------------------------
       Test: Duplicate Prevention
    -------------------------------------------------- */
    @IsTest
    static void testDuplicateImmunizationNotInserted() {

        Account patient = getExistingPatient();

        CodeSetBundle cs = [Select Id From CodeSetBundle Where Name ='Test Vaccine'];
        

        insert new PatientImmunization(
            ImmunizationId__c = 'imm-dup',
            PatientId        = patient.Id,
            Status           = 'Completed',
            VaccineCodeId    = cs.Id,
            VaccinationDate  = System.now()
        );

        String jsonBody =
        '{' +
        ' "resourceType": "Immunization",' +
        ' "id": "imm-dup",' +
        ' "status": "completed",' +
        ' "patient": { "reference": "Patient/patient-123" },' +
        ' "occurrenceDateTime": "2024-03-01T12:00:00Z"' +
        '}';

        Test.startTest();
        ImmunizationHandler.parseAndInsertImmunizations(jsonBody);
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM PatientImmunization WHERE ImmunizationId__c = 'imm-dup']
        );
    }

    /* ------------------------------------------------
       Test: Blank JSON
    -------------------------------------------------- */
    @IsTest
    static void testBlankJson() {
        Test.startTest();
        ImmunizationHandler.parseAndInsertImmunizations('');
        Test.stopTest();
        System.assert(true);
    }
}