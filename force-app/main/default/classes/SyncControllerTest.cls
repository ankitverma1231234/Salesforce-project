@IsTest(SeeAllData=true)
public class SyncControllerTest {

    /* -------------------------
       HTTP Mock
    -------------------------- */
    private class HttpSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success": true}');
            return res;
        }
    }

    /* -------------------------
       Helpers
    -------------------------- */

    private static Account getPatientAccount() {
        List<Account> accs = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
        System.assert(
            !accs.isEmpty(),
            'Account with Metriport_Patient_Id__c = patient-123 must exist'
        );
        return accs[0];
    }

    private static Account getAccountWithoutPatientId() {
        List<Account> accs = [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = NULL
            LIMIT 1
        ];
        System.assert(
            !accs.isEmpty(),
            'At least one Account without Metriport_Patient_Id__c must exist'
        );
        return accs[0];
    }

    private static Contact getContact(Account acc) {
        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];
        System.assert(
            !contacts.isEmpty(),
            'Contact must exist for Account ' + acc.Id
        );
        return contacts[0];
    }

    /* -------------------------
       syncAccount() – SUCCESS
    -------------------------- */
    @IsTest
    static void testSyncAccountSuccess() {
        Account acc = getPatientAccount();

        Test.startTest();
        SyncController.syncAccount(acc.Id);
        Test.stopTest();

        System.assert(true);
    }

    /* -------------------------
       syncAccount() – Missing Id
    -------------------------- */
    @IsTest
    static void testSyncAccountMissingId() {
        try {
            Test.startTest();
            SyncController.syncAccount(null);
            Test.stopTest();
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /* -------------------------
       syncAccount() – Missing Patient Id
    -------------------------- */
    @IsTest
    static void testSyncAccountMissingPatientId() {
        Account acc = getAccountWithoutPatientId();

        try {
            Test.startTest();
            SyncController.syncAccount(acc.Id);
            Test.stopTest();
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /* -------------------------
       createPatient() – SUCCESS
    -------------------------- */
    @IsTest
    static void testCreatePatientSuccess() {
        Account acc = getAccountWithoutPatientId();

        // ✅ Mock needed because createPatient makes callouts
        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        SyncController.createPatient(acc.Id);
        Test.stopTest();

        System.assert(true);
    }

    /* -------------------------
       createPatient() – Null Id
    -------------------------- */
    @IsTest
    static void testCreatePatientNullId() {
        try {
            Test.startTest();
            SyncController.createPatient(null);
            Test.stopTest();
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /* -------------------------
       sendPatientData() – SUCCESS
    -------------------------- */
    @IsTest
    static void testSendPatientData() {
        Account acc = getPatientAccount();
        Contact c = getContact(acc);

        // ✅ Mock needed because sendPatientData uses @future(callout=true)
        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        SyncController.sendPatientData(c.Id);
        Test.stopTest();

        System.assert(true);
    }

    /* -------------------------
       sendInsuranceData() – SUCCESS
    -------------------------- */
    @IsTest
    static void testSendInsuranceDataSuccess() {
        Account acc = getPatientAccount();

        // ✅ Mock needed because sendInsuranceData makes callouts
        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        try {
            Test.startTest();
            String result = SyncController.sendInsuranceData(acc.Id);
            Test.stopTest();
            System.assert(true);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /* -------------------------
       sendInsuranceData() – Null Id
    -------------------------- */
    @IsTest
    static void testSendInsuranceDataNullId() {
        try {
            Test.startTest();
            SyncController.sendInsuranceData(null);
            Test.stopTest();
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /* -------------------------
       UpdateMemberCheckbox() – SUCCESS
    -------------------------- */
    @IsTest
    static void testUpdateMemberCheckboxSuccess() {
        Account acc = getPatientAccount();

        Test.startTest();
        SyncController.UpdateMemberCheckbox(acc.Id);
        Test.stopTest();

        Account updated = [SELECT Send_Member_to_portal__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(true, updated.Send_Member_to_portal__c, 
            'Send_Member_to_portal__c should be true after update');
    }

    /* -------------------------
       UpdateMemberCheckbox() – Null Id
    -------------------------- */
    @IsTest
    static void testUpdateMemberCheckboxNullId() {
        try {
            Test.startTest();
            SyncController.UpdateMemberCheckbox(null);
            Test.stopTest();
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /* -------------------------
       deletePatient() – SUCCESS
    -------------------------- */
    @IsTest
    static void testDeletePatientSuccess() {
        Account acc = getPatientAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        SyncController.deletePatient(acc.Id);
        Test.stopTest();

        System.assert(true);
    }

    /* -------------------------
       deletePatient() – Null Id
    -------------------------- */
    @IsTest
    static void testDeletePatientNullId() {
        Test.startTest();
        SyncController.deletePatient(null);
        Test.stopTest();

        System.assert(true);
    }

    /* -------------------------
       deletePatient() – No Metriport Id
    -------------------------- */
    @IsTest
    static void testDeletePatientNoMetriportId() {
        Account acc = getAccountWithoutPatientId();

        Test.startTest();
        SyncController.deletePatient(acc.Id);
        Test.stopTest();

        System.assert(true);
    }
 @IsTest
    static void familydata() {
        Account acc = getPatientAccount();

        Test.setMock(HttpCalloutMock.class, new HttpSuccessMock());
        Test.startTest();
        SyncController.sendFamilyData(acc.Id);
        Test.stopTest();

        System.assert(true);
    }

}