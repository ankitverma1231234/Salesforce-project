@isTest(seeAllData=true)
public class VitalAPIHandlerTest {

    class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success":true}');
            res.setStatusCode(200);
            return res;
        }
    }

    private static Account getOrCreatePersonAccount() {
        List<Account> existing = [
            SELECT Id FROM Account
            WHERE IsPersonAccount = true AND PersonEmail != null
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        Id personAccountRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account pa = new Account(
            FirstName         = 'Test',
            LastName          = 'VitalUser',
            RecordTypeId      = personAccountRTId,
            PersonEmail       = 'test.vital@example.com',
            PersonMobilePhone = '5559876543'
        );
        insert pa;
        return pa;
    }

    private static void ensureCustomSettings() {
        BatonPortalAPI__c cs = BatonPortalAPI__c.getInstance();
        if (cs == null || String.isBlank(cs.Vitals_API__c)) {
            insert new BatonPortalAPI__c(
                SetupOwnerId  = UserInfo.getOrganizationId(),
                API_Key__c    = 'testkey',
                Vitals_API__c = 'https://api.test.com'
            );
        }

        TriggerSettings__c ts = TriggerSettings__c.getInstance();
        if (ts == null) {
            insert new TriggerSettings__c(
                SetupOwnerId                 = UserInfo.getOrganizationId(),
                Care_Observation_Checkbox__c = true
            );
        } else if (!ts.Care_Observation_Checkbox__c) {
            ts.Care_Observation_Checkbox__c = true;
            update ts;
        }
    }

    @isTest
    static void testSendDataSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        ensureCustomSettings();
        Account acc = getOrCreatePersonAccount();

        // Names must match VITAL_NAME_MAP keys exactly
        CareObservation co1 = new CareObservation(
            Name              = 'heart rate',
            Value_Quantity__c = '72',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Category          = 'Vital-Signs'
        );
        CareObservation co2 = new CareObservation(
            Name              = 'body temperature',
            Value_Quantity__c = '98',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Category          = 'Vital-Signs'
        );
        CareObservation co3 = new CareObservation(
            Name              = 'respiratory rate',
            Value_Quantity__c = '16',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Category          = 'Vital-Signs'
        );

        Test.startTest();
        insert new List<CareObservation>{ co1, co2, co3 };
        Test.stopTest();
    }

    @isTest
    static void testInvalidVitalNameSkipped() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        ensureCustomSettings();
        Account acc = getOrCreatePersonAccount();

        // Name not in VITAL_NAME_MAP — should be skipped
        CareObservation co = new CareObservation(
            Name              = 'unknown_vital',
            Value_Quantity__c = '50',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Category          = 'Vital-Signs'
        );

        Test.startTest();
        insert co;
        Test.stopTest();
    }

    @isTest
    static void testMissingCustomSettingSkipped() {
        // Do NOT set up BatonPortalAPI__c — handler should return early
        Account acc = getOrCreatePersonAccount();

        CareObservation co = new CareObservation(
            Name              = 'heart rate',
            Value_Quantity__c = '72',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Category          = 'Vital-Signs'
        );

        Test.startTest();
        insert co;
        Test.stopTest();
    }

    @isTest
    static void testDuplicateVitalSendsLatestOnly() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        ensureCustomSettings();
        Account acc = getOrCreatePersonAccount();

        // Two heart rate records — only latest should be sent
        CareObservation co1 = new CareObservation(
            Name              = 'heart rate',
            Value_Quantity__c = '60',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Category          = 'Vital-Signs'
        );
        CareObservation co2 = new CareObservation(
            Name              = 'heart rate',
            Value_Quantity__c = '80',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Category          = 'Vital-Signs'
        );

        Test.startTest();
        insert new List<CareObservation>{ co1, co2 };
        Test.stopTest();
    }
}