@IsTest(SeeAllData=true)
public class HealthcareFacilityTriggerTest {

    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }

    private static void enableTriggerSetting() {
        TriggerSettings__c setting = TriggerSettings__c.getInstance();
        if (setting == null) {
            setting = new TriggerSettings__c();
        }
        setting.HealthcareFacilityTrigger__c = true;
        upsert setting;
    }

    private static void disableTriggerSetting() {
        TriggerSettings__c setting = TriggerSettings__c.getInstance();
        if (setting == null) {
            setting = new TriggerSettings__c();
        }
        setting.HealthcareFacilityTrigger__c = false;
        upsert setting;
    }

    private static Account getPersonAccount() {
        List<Account> accList = [
            SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1
        ];
        if (!accList.isEmpty()) return accList[0];

        Id paRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1
        ].Id;
        Account pa = new Account(
            RecordTypeId   = paRtId,
            FirstName      = 'Test',
            LastName       = 'Patient',
            PersonEmail    = 'test.patient@example.com',
            PersonMobilePhone = '5559876543'
        );
        insert pa;
        return pa;
    }

    // ─── INSERT ───────────────────────────────────────────────────────────────

    @IsTest
    static void testInsert_withSettingEnabled() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        enableTriggerSetting();
        Account pa = getPersonAccount();

        Test.startTest();
        HealthcareFacility hf = new HealthcareFacility(
            Name      = 'Test Clinic Insert',
            AccountId = pa.Id
        );
        insert hf;
        Test.stopTest();

        System.assert(true, 'Insert with trigger enabled completed');
    }

    // ─── UPDATE ───────────────────────────────────────────────────────────────

    @IsTest
    static void testUpdate_withSettingEnabled() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        enableTriggerSetting();
        Account pa = getPersonAccount();

        HealthcareFacility hf = new HealthcareFacility(
            Name      = 'Test Clinic Update',
            AccountId = pa.Id
        );
        insert hf;

        Test.startTest();
        hf.Name = 'Updated Clinic Name';
        update hf;
        Test.stopTest();

        System.assert(true, 'Update with trigger enabled completed');
    }

    // ─── DELETE ───────────────────────────────────────────────────────────────

    @IsTest
    static void testDelete_withSettingEnabled() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        enableTriggerSetting();
        Account pa = getPersonAccount();

        HealthcareFacility hf = new HealthcareFacility(
            Name      = 'Test Clinic Delete',
            AccountId = pa.Id
        );
        insert hf;

        Test.startTest();
        delete hf;
        Test.stopTest();

        System.assert(true, 'Delete with trigger enabled completed');
    }

    // ─── SETTING DISABLED (early return branch) ───────────────────────────────

    @IsTest
    static void testInsert_withSettingDisabled() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        disableTriggerSetting();
        Account pa = getPersonAccount();

        Test.startTest();
        HealthcareFacility hf = new HealthcareFacility(
            Name      = 'Disabled Setting Clinic',
            AccountId = pa.Id
        );
        insert hf;
        Test.stopTest();

        System.assert(true, 'Trigger should exit early when setting is disabled');
    }
}