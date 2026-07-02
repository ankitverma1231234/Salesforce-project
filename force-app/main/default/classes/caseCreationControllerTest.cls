@IsTest(SeeAllData=true)
public class caseCreationControllerTest {

    /* ============================================================
       HTTP CALLOUT MOCK
       ============================================================ */
    private class PdfMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/pdf');
            res.setBodyAsBlob(Blob.valueOf('Dummy PDF'));
            return res;
        }
    }

    /* ============================================================
       HELPER: GET OR CREATE PERSON ACCOUNT (SeeAllData=true pattern)
       ============================================================ */
    private static Account getPersonAccount() {

        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];

        if (!existingAccounts.isEmpty()) {
            return existingAccounts[0];
        }

        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account pa = new Account(
            RecordTypeId        = personAccountRT,
            FirstName           = 'Existing',
            LastName            = 'Test',
            PersonEmail         = 'existing.test@example.com',
            PersonMobilePhone   = '5551234567'
        );
        insert pa;

        return pa;
    }
    private static AllergyIntolerance getOrCreateAllergy(Id accountId) {
        List<AllergyIntolerance> listAI = [
            SELECT Id FROM AllergyIntolerance
            WHERE PatientId = :accountId
            LIMIT 1];
        if (!listAI.isEmpty()) return listAI[0];
        AllergyIntolerance ai = new AllergyIntolerance(
            PatientId = accountId,
            Combine_allergy_and_Generic__c = 'Dust Allergy',
            Severity = 'Mild',
            Reaction__c = 'Sneezing'
        );
        insert ai;
        return ai;
    }
    private static MedicationStatement getOrCreateMedication(Id accountId) {
        Medication med = [SELECT Id FROM Medication LIMIT 1];
        if (med == null) {
            med = new Medication(Name = 'Paracetamol');
            insert med;
        }
        List<MedicationStatement> listMS = [
            SELECT Id FROM MedicationStatement
            WHERE PatientId = :accountId
            LIMIT 1];
        if (!listMS.isEmpty()) return listMS[0];
        MedicationStatement ms = new MedicationStatement(
            PatientId = accountId,
            MedicationId = med.Id,
            Dose__c = '500mg',
            Frequency__c = 'Once Daily',
            Status = 'Active'
        );
        insert ms;
        return ms;
    }
    private static HealthCondition getOrCreateCondition(Id accountId) {
        List<HealthCondition> listHC = [
            SELECT Id FROM HealthCondition
            WHERE PatientId = :accountId
            LIMIT 1];
        if (!listHC.isEmpty()) return listHC[0];
        HealthCondition hc = new HealthCondition(
            PatientId = accountId,
            ProblemName = 'Diabetes',
            ConditionStatus = 'Active'
        );
        insert hc;
        return hc;
    }

    private static HealthCareProcedure getOrCreateProcedure() {
        List<HealthCareProcedure> listHCP = [
            SELECT Id FROM HealthCareProcedure LIMIT 1
        ];

        if (!listHCP.isEmpty()) return listHCP[0];

        HealthCareProcedure proc = new HealthCareProcedure(
            Name = 'Knee Surgery',
            EffectiveDate = Date.today()
        );
        insert proc;
        return proc;
    }

    /* ============================================================
       TEST: GET PERSON ACCOUNT
       ============================================================ */
    @IsTest
    static void testGetPersonAccount() {
        Account acc = getPersonAccount();

        Test.startTest();
        Account result = caseCreationController.getPersonAccount(acc.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(acc.Id, result.Id);
    }

    /* ============================================================
       TEST: CREATE CASE
       ============================================================ */
    @IsTest
    static void testCreateCase() {

        Account acc = getPersonAccount();

        AllergyIntolerance allergy = getOrCreateAllergy(acc.Id);
        MedicationStatement medication = getOrCreateMedication(acc.Id);
        HealthCondition condition = getOrCreateCondition(acc.Id);
        HealthCareProcedure procedure = getOrCreateProcedure();

        List<String> allergyIds   = new List<String>{ allergy.Id };
        List<String> medicationIds = new List<String>{ medication.Id };
        List<String> conditionIds = new List<String>{ condition.Id };
        List<String> procedureIds = new List<String>{ procedure.Id };

        Test.setMock(HttpCalloutMock.class, new PdfMock());

        Test.startTest();
        Id caseId = caseCreationController.createCase(
            acc.Id,
            'Test User',
            'test@test.com',
            '1995-01-01',
            'Mumbai',
            'MH',
            'India',
            '400001',
            'Street 1',
            '9999999999',
            'Maiden',
            'Male',
            'Test Notes',
            'AI Summary Here', 
            JSON.serialize(allergyIds),
            JSON.serialize(medicationIds),
            JSON.serialize(conditionIds),
            JSON.serialize(procedureIds)
        );
        Test.stopTest();

        System.assertNotEquals(null, caseId);
    }

    /* ============================================================
       TEST: QUERY METHODS
       ============================================================ */
    @IsTest
    static void testQueryMethods() {

        Account acc = getPersonAccount();

        Test.startTest();
        caseCreationController.getAllergies(acc.Id);
        caseCreationController.getMedications(acc.Id);
        caseCreationController.getHealthConditions(acc.Id);
        caseCreationController.getHealthCareProcedures(acc.Id);
        Test.stopTest();

        System.assert(true);
    }
}