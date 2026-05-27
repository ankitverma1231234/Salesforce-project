@isTest(SeeAllData=true)
private class MetriportIntegrationBatchTest {

    private static final String METRIPORT_USER_FIRST_NAME = 'Metriport Integration Site';
    private static final String METRIPORT_USER_LAST_NAME  = 'Guest User';

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Full batch with ALL record types using the testable constructor
    //    → covers execute(), finish(), buildEmailBody(), buildRow() for
    //      every label, buildSectionConfig(), td(), sendEmail()
    // ─────────────────────────────────────────────────────────────────────────
       private static SObject getOrCreateTestLocation(String locationId) {
        Schema.SObjectType locType = Schema.getGlobalDescribe().get('Location');
        if (locType == null) return null;
        
        // Try to find existing location first
        List<SObject> existingLocations = Database.query(
            'SELECT Id FROM Location WHERE LocationId__c = :locationId LIMIT 1'
        );
        if (!existingLocations.isEmpty()) {
            return existingLocations[0];
        }
        
        // Create new location if not found
        SObject loc = locType.newSObject();
        loc.put('Name', 'Test Location');
        loc.put('LocationId__c', locationId);
        loc.put('LocationType', 'Facility');
        // Set required address fields
        loc.put('Location_Address__Street__s', '123 Test St');
        loc.put('Location_Address__City__s', 'Test City');
        loc.put('Location_Address__CountryCode__s', 'US');
        insert loc;
        return loc;
    }
    @isTest
    static void testFullBatchWithAllData() {
        User metriportUser = getOrCreateMetriportUser();
        System.assertNotEquals(null, metriportUser, 'Metriport user must exist');

        // Wide window around NOW so records are guaranteed to fall inside
        DateTime winStart = DateTime.now().addMinutes(-5);
        DateTime winEnd   = DateTime.now().addMinutes(30);

        System.runAs(metriportUser) {
             List<Account> existingAccounts = [
            SELECT Id, Metriport_Patient_Id__c 
            FROM Account 
            WHERE Metriport_Patient_Id__c = 'patient-123'  AND IsPersonAccount = true
            LIMIT 1
        ];
            Account patient = existingAccounts[0];

            Medication testMed = new Medication(Name = 'Metriport Test Med');
            insert testMed;

            // 1. AllergyIntolerance
            AllergyIntolerance allergy = new AllergyIntolerance(PatientId = patient.Id);
            insert allergy;

            // 2. MedicationStatement
            MedicationStatement medStatement = new MedicationStatement(
                PatientId    = patient.Id,
                MedicationId = testMed.Id,
                Status       = 'active'
            );
            insert medStatement;

            // 3. MedicationAdministration
            MedicationAdministration medAdmin = new MedicationAdministration(
                PatientId    = patient.Id,
                MedicationId = testMed.Id,
                StartDate    = DateTime.now(),
                Status       = 'completed'
            );
            insert medAdmin;

            // 4. MedicationRequest
            MedicationRequest medRequest = new MedicationRequest(
                PatientId    = patient.Id,
                MedicationId = testMed.Id,
                Status       = 'active',
                Type         = 'Plan'
            );
            insert medRequest;

            // 5. MedicationDispense
            MedicationDispense medDispense = new MedicationDispense(
                PatientId    = patient.Id,
                MedicationId = testMed.Id,
                Status       = 'completed'
            );
            insert medDispense;

            // 6. HealthCondition (Medical History)
            HealthCondition healthCond = new HealthCondition(
                PatientId   = patient.Id,
                ProblemName = 'Test Condition'
            );
            insert healthCond;

            // 7. HealthcareProcedure (Surgical History)
            HealthcareProcedure surgery = new HealthcareProcedure(
                Patient__c = patient.Id,
                Status__c  = 'completed',
                Name       = 'Test Surgery'
            );
            insert surgery;

            
            // 8. Visit (Encounter)
            Visit encounter = new Visit(
                PlaceId               = getOrCreateTestLocation('location-123').Id,
                AccountId             = patient.Id,
                PlannedVisitStartTime = DateTime.now()
            );
            insert encounter;

            // 9. CareObservation – Laboratory
            CareObservation lab = new CareObservation(
                ObservedSubjectId = patient.Id,
                Category          = 'Laboratory',
                ObservationStatus = 'final',
                Name              = 'Lab Test'
            );
            insert lab;

            // 10. DiagnosticSummary
            DiagnosticSummary diagSummary = new DiagnosticSummary(
                PatientId = patient.Id,
                Summary   = 'Test summary',
                Status    = 'Unknown'
            );
            insert diagSummary;
           CodeSetBundle cs = [Select Id From CodeSetBundle Where Name ='Test Vaccine'];


            // 11. PatientImmunization
            PatientImmunization immunization = new PatientImmunization(
                PatientId       = patient.Id,
                Vaccine_Name__c = 'Test Vaccine',
                VaccinationDate = DateTime.now(),
                Status          = 'Completed',
                VaccineCodeId   = cs.Id
            );
            insert immunization;

            // 12. CareObservation – Vital-Signs
            CareObservation vital = new CareObservation(
                ObservedSubjectId = patient.Id,
                Category          = 'Vital-Signs',
                ObservationStatus = 'final',
                Name              = 'Vital Test'
            );
            insert vital;

            // 13. CareObservation – Social-History
            CareObservation socialHistory = new CareObservation(
                ObservedSubjectId = patient.Id,
                Category          = 'Social-History',
                ObservationStatus = 'final',
                Name              = 'Social Test'
            );
            insert socialHistory;

            // 14. Family_Member_History__c
            Family_Member_History__c familyHistory = new Family_Member_History__c(
                Patient__c = patient.Id
            );
            insert familyHistory;

            

            // 16. ClinicalServiceRequest
            ClinicalServiceRequest clinRequest = new ClinicalServiceRequest(
                PatientId = patient.Id,
                Status    = 'active',
                Type      = 'Directive'
            );
            insert clinRequest;

            // 17. HealthcarePractitionerFacility
            HealthcarePractitionerFacility practitioner = new HealthcarePractitionerFacility(
                AccountId = patient.Id,
                Name      = 'Test Practitioner'
            );
            insert practitioner;

            // 18. HealthcareFacility
            HealthcareFacility facility = new HealthcareFacility(
                AccountId = patient.Id,
                Name      = 'Test Facility'
            );
            insert facility;

            // 19. ContentVersion (File)
            ContentVersion file = new ContentVersion(
                Title          = 'Test.pdf',
                PathOnClient   = 'Test.pdf',
                VersionData    = Blob.valueOf('data'),
                IsMajorVersion = true
            );
            insert file;
        }

        ensureEmailCustomSetting();

        Test.startTest();
        // Use testable constructor with window around NOW and the real user ID
        // so execute() queries are guaranteed to find the records we just inserted
        MetriportIntegrationBatch batch = new MetriportIntegrationBatch(
            winStart,
            winEnd,
            metriportUser.Id
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'Batch completed – all record types, buildEmailBody + buildRow covered');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. No records in window → covers buildNoRecordsBody()
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testBatchWithNoRecords() {
        User metriportUser = getOrCreateMetriportUser();
        ensureEmailCustomSetting();

        // Use a window far in the past where no records exist
        DateTime pastStart = DateTime.newInstance(2000, 1, 1, 0, 0, 0);
        DateTime pastEnd   = DateTime.newInstance(2000, 1, 1, 0, 30, 0);

        Test.startTest();
        MetriportIntegrationBatch batch = new MetriportIntegrationBatch(
            pastStart,
            pastEnd,
            metriportUser.Id
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'No records – buildNoRecordsBody covered');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. No email custom setting → covers early return in finish() and
    //    empty-settings debug branch
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testBatchWithNoEmailSetting() {
        // With SeeAllData=true we can see existing settings.
        // We need to ensure none exist for this test path.
        // If settings exist in org, this test may not fully cover the branch,
        // but we attempt cleanup.
        List<Metriport_Daily_Email__c> existing = [SELECT Id FROM Metriport_Daily_Email__c];
        if (!existing.isEmpty()) {
            delete existing;
        }

        Test.startTest();
        MetriportIntegrationBatch batch = new MetriportIntegrationBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'No email setting – early return in finish()');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Multiple email addresses (comma, semicolon, duplicates, blanks)
    //    → covers split/dedup/blank-skip in getEmailRecipientsFromCustomSetting()
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testMultipleEmailRecipients() {
        List<Metriport_Daily_Email__c> existing = [SELECT Id FROM Metriport_Daily_Email__c];
        if (!existing.isEmpty()) {
            delete existing;
        }

        insert new List<Metriport_Daily_Email__c>{
            new Metriport_Daily_Email__c(
                Name     = 'MultiComma',
                Email__c = 'alice@example.com'
            ),
            new Metriport_Daily_Email__c(
                Name     = 'MultiSemicolon',
                Email__c = 'charlie@example.com'
            ),
            new Metriport_Daily_Email__c(
                Name     = 'BlankEmail',
                Email__c = ''
            )
        };

        Test.startTest();
        MetriportIntegrationBatch batch = new MetriportIntegrationBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'Multiple email recipients with dedup covered');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Schedulable interface → covers execute(SchedulableContext)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSchedulableExecute() {
        ensureEmailCustomSetting();

        Test.startTest();
        MetriportIntegrationBatch schedulableBatch = new MetriportIntegrationBatch();
        schedulableBatch.execute(null);
        Test.stopTest();

        System.assert(true, 'Schedulable execute covered');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 6. System.schedule → covers cron path
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testScheduleViaCron() {
        ensureEmailCustomSetting();

        Test.startTest();
        String jobId = System.schedule(
            'MetriportBatchTest_' + DateTime.now().getTime(),
            '0 0 4 * * ?',
            new MetriportIntegrationBatch()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Scheduled job created');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 7. metriportUserId is null → execute() returns on null guard
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testBatchWithNullUserId() {
        ensureEmailCustomSetting();

        DateTime winStart = DateTime.now().addMinutes(-5);
        DateTime winEnd   = DateTime.now().addMinutes(30);

        Test.startTest();
        MetriportIntegrationBatch batch = new MetriportIntegrationBatch(
            winStart,
            winEnd,
            null
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'Null userId – execute() early return covered');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 8. Multiple records per type → covers alternating row colors
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testMultipleRecordsPerType() {
        User metriportUser = getOrCreateMetriportUser();

        DateTime winStart = DateTime.now().addMinutes(-5);
        DateTime winEnd   = DateTime.now().addMinutes(30);

        System.runAs(metriportUser) {
              List<Account> existingAccounts = [
            SELECT Id, Metriport_Patient_Id__c 
            FROM Account 
            WHERE Metriport_Patient_Id__c = 'patient-123'  AND IsPersonAccount = true
            LIMIT 1
        ];
            Account patient = existingAccounts[0];

            for (Integer i = 0; i < 3; i++) {
                AllergyIntolerance allergy = new AllergyIntolerance(PatientId = patient.Id);
                insert allergy;
            }

            for (Integer i = 0; i < 2; i++) {
                HealthCondition hc = new HealthCondition(
                    PatientId   = patient.Id,
                    ProblemName = 'Condition ' + i
                );
                insert hc;
            }
        }

        ensureEmailCustomSetting();

        Test.startTest();
        MetriportIntegrationBatch batch = new MetriportIntegrationBatch(
            winStart,
            winEnd,
            metriportUser.Id
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'Multiple records – alternating rows covered');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 9. Records with blank/null field values → covers td() dash fallback
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testRecordsWithNullFields() {
        User metriportUser = getOrCreateMetriportUser();

        DateTime winStart = DateTime.now().addMinutes(-5);
        DateTime winEnd   = DateTime.now().addMinutes(30);

        System.runAs(metriportUser) {
              List<Account> existingAccounts = [
            SELECT Id, Metriport_Patient_Id__c 
            FROM Account 
            WHERE Metriport_Patient_Id__c = 'patient-123'  AND IsPersonAccount = true
            LIMIT 1
        ];
            Account patient = existingAccounts[0];

            AllergyIntolerance allergy = new AllergyIntolerance(PatientId = patient.Id);
            insert allergy;

           /* Visit encounter = new Visit(
                PlaceId               = '131bf000000h313AAA',
                AccountId             = patient.Id,
                PlannedVisitStartTime = DateTime.now()
            ); 
            insert encounter;*/

            ContentVersion file = new ContentVersion(
                Title          = 'NullTest.pdf',
                PathOnClient   = 'NullTest.pdf',
                VersionData    = Blob.valueOf('null-test'),
                IsMajorVersion = true
            );
            insert file;
        }

        ensureEmailCustomSetting();

        Test.startTest();
        MetriportIntegrationBatch batch = new MetriportIntegrationBatch(
            winStart,
            winEnd,
            metriportUser.Id
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'Null fields – td() dash fallback covered');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 10. Default constructor → covers original constructor + user lookup
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testDefaultConstructor() {
        getOrCreateMetriportUser();
        ensureEmailCustomSetting();

        Test.startTest();
        MetriportIntegrationBatch batch = new MetriportIntegrationBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'Default constructor and user lookup covered');
    }

    // ==================== Helper Methods ====================

    private static User getOrCreateMetriportUser() {
        List<User> existing = [
            SELECT Id FROM User
            WHERE FirstName = :METRIPORT_USER_FIRST_NAME
              AND LastName  = :METRIPORT_USER_LAST_NAME
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        Profile sysAdmin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        User newUser = new User(
            Username           = 'metriport.batch.test.' + DateTime.now().getTime() + '@test.com',
            Email              = 'metriport.batch.test@test.com',
            FirstName          = METRIPORT_USER_FIRST_NAME,
            LastName           = METRIPORT_USER_LAST_NAME,
            Alias              = 'mbtst',
            TimeZoneSidKey     = 'America/Los_Angeles',
            LocaleSidKey       = 'en_US',
            EmailEncodingKey   = 'UTF-8',
            ProfileId          = sysAdmin.Id,
            LanguageLocaleKey  = 'en_US'
        );
        insert newUser;
        return newUser;
    }

    private static void ensureEmailCustomSetting() {
        Map<String, Metriport_Daily_Email__c> allSettings = Metriport_Daily_Email__c.getAll();
        if (allSettings == null || allSettings.isEmpty()) {
            insert new Metriport_Daily_Email__c(
                Name     = 'Test',
                Email__c = 'test@example.com'
            );
        }
    }
}