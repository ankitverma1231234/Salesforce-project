@isTest(SeeAllData=true)
public class VisitTiggerHandlerTest {

    /**
     * Helper: Query the known Person Account and return it.
     */
    private static Account getPersonAccount() {
        List<Account> accs = [
            SELECT Id, Name, Phone, PersonEmail, PersonContactId, IsPersonAccount
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
              AND IsPersonAccount = true
            LIMIT 1
        ];
        System.assert(!accs.isEmpty(), 'Expected a Person Account with Metriport_Patient_Id__c = patient-123');
        return accs[0];
    }

    /**
     * Helper: Build a Visit record with all required fields populated.
     *         Adjust this method if your org has additional required fields / validation rules.
     */
    private static Visit buildVisit(Id accountId, Boolean adtNotify) {
        Visit v       = new Visit();
        v.AccountId   = accountId;
        v.ADT_Notify__c = adtNotify;

        // Standard required fields on Visit
        v.PlannedVisitStartTime = Datetime.now();
        v.PlannedVisitEndTime   = Datetime.now().addHours(1);

        // If your org requires VisitorId, PlaceId, or other fields,
        // uncomment and set them below:
        // v.VisitorId = <some_user_or_contact_id>;
        // v.PlaceId   = <some_place_id>;

        return v;
    }

    /**
     * Test 1: Full happy-path – SMS + Email enabled, qualifying Visit,
     *         Person Account has Emergency Contacts with Phone & Email.
     */
    @isTest
    static void testHandleAfterInsert_FullPath() {

        Account personAcc = getPersonAccount();

        // Confirm Emergency Contacts exist
        List<Contact> emergencyContacts = [
            SELECT Id, Phone, Email
            FROM Contact
            WHERE AccountId = :personAcc.Id
              AND Emergency_Contact__c = true
        ];
        System.assert(!emergencyContacts.isEmpty(),
            'Expected at least one Emergency Contact for the Person Account');

        Visit testVisit = buildVisit(personAcc.Id, true);

        Test.startTest();
        insert testVisit;
        Test.stopTest();

        // Verify SMS records if SMS is enabled
        MessageCustomization__c setting = [
            SELECT Enable_SMS__c, Enable_Email__c,
                   SMS_Template_Id_for_ADT__c, Email_Template_Id_for_ADT__c
            FROM MessageCustomization__c
            LIMIT 1
        ];

        if (setting.Enable_SMS__c && setting.SMS_Template_Id_for_ADT__c != null) {
            List<sra__Message_History__c> smsRecords = [
                SELECT Id, sra__Message_Body__c, sra__Receiver_Number__c
                FROM sra__Message_History__c
                WHERE sra__Related_Object_Id__c = :testVisit.Id
            ];
            Integer contactsWithPhone = 0;
            for (Contact c : emergencyContacts) {
                if (String.isNotBlank(c.Phone)) contactsWithPhone++;
            }
            System.assertEquals(contactsWithPhone, smsRecords.size(),
                'Expected one SMS record per emergency contact with a phone number');
        }
    }

    /**
     * Test 2: ADT_Notify__c = false – exits early, no processing.
     */
    @isTest
    static void testHandleAfterInsert_NotifyFalse() {

        Account personAcc = getPersonAccount();
        Visit testVisit   = buildVisit(personAcc.Id, false);

        Test.startTest();
        insert testVisit;
        Test.stopTest();

        List<sra__Message_History__c> smsRecords = [
            SELECT Id
            FROM sra__Message_History__c
            WHERE sra__Related_Object_Id__c = :testVisit.Id
        ];
        System.assertEquals(0, smsRecords.size(),
            'No SMS records expected when ADT_Notify__c is false');
    }

    /**
     * Test 3: ADT_Notify__c = null – covers the null-check branch.
     */
    @isTest
    static void testHandleAfterInsert_NotifyNull() {

        Account personAcc = getPersonAccount();
        Visit testVisit   = buildVisit(personAcc.Id, null);

        Test.startTest();
        insert testVisit;
        Test.stopTest();

        List<sra__Message_History__c> smsRecords = [
            SELECT Id
            FROM sra__Message_History__c
            WHERE sra__Related_Object_Id__c = :testVisit.Id
        ];
        System.assertEquals(0, smsRecords.size(),
            'No SMS records expected when ADT_Notify__c is null');
    }

    /**
     * Test 4: buildVisitMergeMap – valid Visit + valid Contact.
     */
    @isTest
    static void testBuildVisitMergeMap_ValidInputs() {

        Account personAcc = getPersonAccount();

        Contact emergencyContact = [
            SELECT Id, Name, Phone, Email, AccountId
            FROM Contact
            WHERE AccountId = :personAcc.Id
              AND Emergency_Contact__c = true
            LIMIT 1
        ];

        Visit testVisit = buildVisit(personAcc.Id, true);
        insert testVisit;

        // Re-query so getPopulatedFieldsAsMap() works correctly
        Visit queriedVisit = [
            SELECT Id, AccountId, ADT_Notify__c,
                   PlannedVisitStartTime, PlannedVisitEndTime
            FROM Visit
            WHERE Id = :testVisit.Id
            LIMIT 1
        ];

        Test.startTest();
        Map<String, String> mergeMap = VisitTiggerHandler.buildVisitMergeMap(queriedVisit, emergencyContact);
        Test.stopTest();

        System.assertNotEquals(null, mergeMap);
        System.assert(mergeMap.size() > 0, 'Merge map should contain tokens');
        System.assert(mergeMap.containsKey('{!id}'),
            'Merge map should contain {!id} token from Visit');
        System.assert(mergeMap.containsKey('{!contact.id}'),
            'Merge map should contain {!contact.id} token from Contact');
    }

    /**
     * Test 5: buildVisitMergeMap – both inputs null.
     */
    @isTest
    static void testBuildVisitMergeMap_NullInputs() {

        Test.startTest();
        Map<String, String> mergeMap = VisitTiggerHandler.buildVisitMergeMap(null, null);
        Test.stopTest();

        System.assertNotEquals(null, mergeMap);
        System.assertEquals(0, mergeMap.size(),
            'Merge map should be empty when both inputs are null');
    }

    /**
     * Test 6: buildVisitMergeMap – null Contact only.
     */
    @isTest
    static void testBuildVisitMergeMap_NullContact() {

        Account personAcc = getPersonAccount();
        Visit testVisit   = buildVisit(personAcc.Id, true);
        insert testVisit;

        Visit queriedVisit = [
            SELECT Id, AccountId
            FROM Visit
            WHERE Id = :testVisit.Id
            LIMIT 1
        ];

        Test.startTest();
        Map<String, String> mergeMap = VisitTiggerHandler.buildVisitMergeMap(queriedVisit, null);
        Test.stopTest();

        System.assert(mergeMap.size() > 0, 'Should contain Visit tokens');
        System.assert(!mergeMap.containsKey('{!contact.id}'),
            'Should not contain contact tokens');
    }

    /**
     * Test 7: buildVisitMergeMap – null Visit only.
     */
    @isTest
    static void testBuildVisitMergeMap_NullVisit() {

        Account personAcc = getPersonAccount();

        Contact emergencyContact = [
            SELECT Id, Name, Phone, Email, AccountId
            FROM Contact
            WHERE AccountId = :personAcc.Id
              AND Emergency_Contact__c = true
            LIMIT 1
        ];

        Test.startTest();
        Map<String, String> mergeMap = VisitTiggerHandler.buildVisitMergeMap(null, emergencyContact);
        Test.stopTest();

        System.assert(mergeMap.size() > 0, 'Should contain Contact tokens');
        System.assert(mergeMap.containsKey('{!contact.id}'),
            'Should contain {!contact.id}');
    }

    /**
     * Test 8: Bulk insert – 5 qualifying Visits at once.
     */
    @isTest
    static void testHandleAfterInsert_BulkInsert() {

        Account personAcc = getPersonAccount();

        List<Visit> visits = new List<Visit>();
        for (Integer i = 0; i < 5; i++) {
            Visit v = buildVisit(personAcc.Id, true);
            v.PlannedVisitStartTime = Datetime.now().addDays(i);
            v.PlannedVisitEndTime   = Datetime.now().addDays(i).addHours(1);
            visits.add(v);
        }

        Test.startTest();
        insert visits;
        Test.stopTest();

        Set<Id> visitIds = new Set<Id>();
        for (Visit v : visits) {
            visitIds.add(v.Id);
        }

        MessageCustomization__c setting = [
            SELECT Enable_SMS__c, SMS_Template_Id_for_ADT__c
            FROM MessageCustomization__c
            LIMIT 1
        ];

        if (setting.Enable_SMS__c && setting.SMS_Template_Id_for_ADT__c != null) {
            List<sra__Message_History__c> smsRecords = [
                SELECT Id
                FROM sra__Message_History__c
                WHERE sra__Related_Object_Id__c IN :visitIds
            ];
            System.assert(smsRecords.size() > 0,
                'Expected SMS records for bulk-inserted qualifying visits');
        }
    }
}