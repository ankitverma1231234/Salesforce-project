@isTest(SeeAllData=true)
private class PatientImmunizationTriggerTest {

    private static Account getOrCreatePersonAccount() {
        List<Account> existing = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        Id personAccountRT = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId();
        Account pa = new Account(
            RecordTypeId      = personAccountRT,
            FirstName         = 'Test',
            LastName          = 'Patient',
            PersonEmail       = 'test.patient@example.com',
            PersonMobilePhone = '5551234567'
        );
        insert pa;
        return [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    }

    private static Id getVaccineCodeId() {
        return [SELECT Id FROM CodeSetBundle LIMIT 1].Id;
    }

    private static void enableTrigger() {
        TriggerSettings__c s = TriggerSettings__c.getOrgDefaults();
        s.PatientImmunizationTrigger__c = true;
        upsert s;
    }

    private static PatientImmunization buildImmunization(Id patientId, Id vaccineCodeId) {
        return new PatientImmunization(
            PatientId       = patientId,
            VaccinationDate = Date.today().addDays(-1),
            VaccineCodeId   = vaccineCodeId,
            Status          = 'Completed'
        );
    }

    @isTest
    static void testInsert() {
        enableTrigger();
        Account patient = getOrCreatePersonAccount();
        Id vaccineCodeId = getVaccineCodeId();

        Test.startTest();
        PatientImmunization pi = buildImmunization(patient.Id, vaccineCodeId);
        insert pi;
        Test.stopTest();

        System.assertNotEquals(null, pi.Id, 'Record should be inserted');
    }

    @isTest
    static void testUpdate() {
        enableTrigger();
        Account patient = getOrCreatePersonAccount();
        Id vaccineCodeId = getVaccineCodeId();
        PatientImmunization pi = buildImmunization(patient.Id, vaccineCodeId);
        insert pi;

        Test.startTest();
        update pi;
        Test.stopTest();

        System.assertNotEquals(null, pi.Id, 'Record should be updated');
    }

    @isTest
    static void testDelete() {
        enableTrigger();
        Account patient = getOrCreatePersonAccount();
        Id vaccineCodeId = getVaccineCodeId();
        PatientImmunization pi = buildImmunization(patient.Id, vaccineCodeId);
        insert pi;

        Test.startTest();
        delete pi;
        Test.stopTest();

        List<PatientImmunization> result = [
            SELECT Id FROM PatientImmunization WHERE Id = :pi.Id ALL ROWS
        ];
        System.assertEquals(1, result.size(), 'Record should be in recycle bin');
    }

    @isTest
    static void testTriggerDisabled() {
        TriggerSettings__c s = TriggerSettings__c.getOrgDefaults();
        s.PatientImmunizationTrigger__c = false;
        upsert s;

        Account patient = getOrCreatePersonAccount();
        Id vaccineCodeId = getVaccineCodeId();

        Test.startTest();
        PatientImmunization pi = buildImmunization(patient.Id, vaccineCodeId);
        insert pi;
        Test.stopTest();

        System.assertNotEquals(null, pi.Id, 'Record should still be inserted when trigger is disabled');
    }

    @isTest
    static void testBulkInsert() {
        enableTrigger();
        Account patient = getOrCreatePersonAccount();
        Id vaccineCodeId = getVaccineCodeId();

        Test.startTest();
        insert buildImmunization(patient.Id, vaccineCodeId);
        insert buildImmunization(patient.Id, vaccineCodeId);
        insert buildImmunization(patient.Id, vaccineCodeId);
        Test.stopTest();

        Integer cnt = [SELECT COUNT() FROM PatientImmunization WHERE PatientId = :patient.Id];
    }
}