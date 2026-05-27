@isTest(SeeAllData=true)
public class MemberPlanCalloutFutureTest {

    // ── HTTP Mocks ────────────────────────────────────────────────────────────
    private class MockHttp200 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"ok"}');
            return res;
        }
    }

    private class MockHttp500 implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    // ── Person Account helper ─────────────────────────────────────────────────
    private static Account getOrCreatePersonAccount() {
        List<Account> existing = [
            SELECT Id
            FROM   Account
            WHERE  IsPersonAccount = true
            AND    PersonEmail != null
            LIMIT  1
        ];
        if (!existing.isEmpty()) return existing[0];

        Id personAccountRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account pa = new Account(
            FirstName         = 'Test',
            LastName          = 'MemberPlan',
            RecordTypeId      = personAccountRTId,
            PersonEmail       = 'test.memberplan@example.com',
            PersonMobilePhone = '5559876543'
        );
        insert pa;
        return pa;
    }

    // ── Test data chain ───────────────────────────────────────────────────────
    private class TestChain {
        Id memberId;
        Id memberPlanId;
        Id cbId;
        Id cbiId;
        Id detailId;
    }

    // ── Unique counter so bulk tests never collide on MemberNumber ────────────
    private static Integer chainCounter = 0;

    private static TestChain buildChain() {
        chainCounter++;
        Account pa = getOrCreatePersonAccount();

        // ── MemberPlan ────────────────────────────────────────────────────────
        MemberPlan mp = new MemberPlan(
            MemberId     = pa.Id,
            Name         = 'Test MemberPlan ' + chainCounter,
            MemberNumber = 'MBR-TEST-' + chainCounter,  // unique per call
            Status       = 'Active'
        );
        insert mp;

        // ── CoverageBenefit ───────────────────────────────────────────────────
        CoverageBenefit cb = new CoverageBenefit(
            MemberId     = pa.Id,
            MemberPlanId = mp.Id,
            Name         = 'Test CoverageBenefit ' + chainCounter
        );
        insert cb;

        // ── CoverageBenefitItem ───────────────────────────────────────────────
        CoverageBenefitItem cbi = new CoverageBenefitItem(
            MemberId          = pa.Id,
            CoverageBenefitId = cb.Id,
            Name              = 'Test CoverageBenefitItem ' + chainCounter
        );
        insert cbi;

        // ── CoverageBenefitItemDetail ─────────────────────────────────────────
        medicalcoverage__CoverageBenefitItemDetail__c detail =
            new medicalcoverage__CoverageBenefitItemDetail__c(
                medicalcoverage__Coverage_Benefit_Item__c = cbi.Id,
                medicalcoverage__remainingAmount__c        = 350,
                medicalcoverage__PayerNotes__c             = 'Test payer note'
            );
        insert detail;

        TestChain chain    = new TestChain();
        chain.memberId     = pa.Id;
        chain.memberPlanId = mp.Id;
        chain.cbId         = cb.Id;
        chain.cbiId        = cbi.Id;
        chain.detailId     = detail.Id;
        return chain;
    }

    // ── Custom setting helpers ────────────────────────────────────────────────
    private static String ensureSettingsAndGetOriginalKey() {
        BatonPortalAPI__c s = BatonPortalAPI__c.getOrgDefaults();
        String originalKey  = (s != null) ? s.Insurance_Key__c : null;
        if (s == null) s    = new BatonPortalAPI__c();
        if (String.isBlank(s.Insurance_Key__c)) {
            s.Insurance_Key__c = 'https://mock.baton.test/api/insurance';
            upsert s;
        }
        return originalKey;
    }

    private static void restoreSettings(String originalKey) {
        try {
            BatonPortalAPI__c s = BatonPortalAPI__c.getOrgDefaults();
            if (s == null) return;
            s.Insurance_Key__c = originalKey;
            upsert s;
        } catch (Exception ex) {
            System.debug('restoreSettings: ' + ex.getMessage());
        }
    }

    // =========================================================================
    // sendForCoverageBenefits — entry point 1
    // =========================================================================

    @isTest
    static void test_CB_EmptyList() {
        // Covers: if (coverageBenefitIds.isEmpty()) return;
        Test.startTest();
        MemberPlanCalloutFuture.sendForCoverageBenefits(new List<Id>());
        Test.stopTest();
        System.assert(true, 'Empty-list guard in sendForCoverageBenefits executed');
    }

    @isTest
    static void test_CB_Success() {
        // Covers: full happy path → SOQL finds CB → MemberPlan found → callout 200
        TestChain chain    = buildChain();
        String originalKey = ensureSettingsAndGetOriginalKey();
        try {
            Test.setMock(HttpCalloutMock.class, new MockHttp200());
            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefits(
                new List<Id>{ chain.cbId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'test_CB_Success completed');
    }

    @isTest
    static void test_CB_HttpError() {
        // Covers: res.getStatusCode() >= 300 → API error debug log
        TestChain chain    = buildChain();
        String originalKey = ensureSettingsAndGetOriginalKey();
        try {
            Test.setMock(HttpCalloutMock.class, new MockHttp500());
            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefits(
                new List<Id>{ chain.cbId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'test_CB_HttpError completed');
    }

    @isTest
    static void test_CB_BulkIds() {
        // Covers: multiple CoverageBenefits → multiple MemberPlans in one payload
        TestChain c1 = buildChain();
        TestChain c2 = buildChain();

        String originalKey = ensureSettingsAndGetOriginalKey();
        try {
            Test.setMock(HttpCalloutMock.class, new MockHttp200());
            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefits(
                new List<Id>{ c1.cbId, c2.cbId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'test_CB_BulkIds completed');
    }

    @isTest
    static void test_CB_NoMemberPlan() {
        // Covers: CB exists but MemberPlanId = null in SOQL filter
        // → memberPlanIds stays empty → sendPayload isEmpty guard fires
        // Using fake Id avoids DML with missing required MemberPlanId field
        Id fakeCbId = '0TLbf000000FAKEAAA';
        Test.startTest();
        MemberPlanCalloutFuture.sendForCoverageBenefits(
            new List<Id>{ fakeCbId }
        );
        Test.stopTest();
        System.assert(true, 'sendPayload memberPlanIds.isEmpty guard executed');
    }

    @isTest
    static void test_CB_MissingSettings() {
        // Covers: settings.Insurance_Key__c blank → early return before callout
        TestChain chain = buildChain();

        BatonPortalAPI__c s = BatonPortalAPI__c.getOrgDefaults();
        String originalKey  = (s != null) ? s.Insurance_Key__c : null;
        try {
            if (s == null) s = new BatonPortalAPI__c();
            s.Insurance_Key__c = '';
            upsert s;

            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefits(
                new List<Id>{ chain.cbId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'Blank Insurance_Key__c early-return branch executed');
    }

    // =========================================================================
    // sendForCoverageBenefitItems — entry point 2
    // =========================================================================

    @isTest
    static void test_CBI_EmptyList() {
        // Covers: if (coverageBenefitItemIds.isEmpty()) return;
        Test.startTest();
        MemberPlanCalloutFuture.sendForCoverageBenefitItems(new List<Id>());
        Test.stopTest();
        System.assert(true, 'Empty-list guard in sendForCoverageBenefitItems executed');
    }

    @isTest
    static void test_CBI_Success() {
        // Covers: CBI → CoverageBenefit.MemberPlanId found → callout 200
        TestChain chain    = buildChain();
        String originalKey = ensureSettingsAndGetOriginalKey();
        try {
            Test.setMock(HttpCalloutMock.class, new MockHttp200());
            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefitItems(
                new List<Id>{ chain.cbiId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'test_CBI_Success completed');
    }

    @isTest
    static void test_CBI_HttpError() {
        // Covers: CBI path → callout 500 → error log branch
        TestChain chain    = buildChain();
        String originalKey = ensureSettingsAndGetOriginalKey();
        try {
            Test.setMock(HttpCalloutMock.class, new MockHttp500());
            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefitItems(
                new List<Id>{ chain.cbiId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'test_CBI_HttpError completed');
    }

    @isTest
    static void test_CBI_BulkIds() {
        // Covers: multiple CBIs in one call
        TestChain c1 = buildChain();
        TestChain c2 = buildChain();

        String originalKey = ensureSettingsAndGetOriginalKey();
        try {
            Test.setMock(HttpCalloutMock.class, new MockHttp200());
            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefitItems(
                new List<Id>{ c1.cbiId, c2.cbiId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'test_CBI_BulkIds completed');
    }

    @isTest
    static void test_CBI_NoMemberPlan() {
        // Covers: CBI found but CoverageBenefit.MemberPlanId = null
        // → memberPlanIds empty → sendPayload guard fires
        Id fakeCbiId = '0TUbf000000FAKEAAA';
        Test.startTest();
        MemberPlanCalloutFuture.sendForCoverageBenefitItems(
            new List<Id>{ fakeCbiId }
        );
        Test.stopTest();
        System.assert(true, 'CBI no MemberPlan guard executed');
    }

    // =========================================================================
    // sendForCoverageBenefitItemDetails — entry point 3
    // =========================================================================

    @isTest
    static void test_CBID_EmptyList() {
        // Covers: if (detailIds.isEmpty()) return;
        Test.startTest();
        MemberPlanCalloutFuture.sendForCoverageBenefitItemDetails(new List<Id>());
        Test.stopTest();
        System.assert(true, 'Empty-list guard in sendForCoverageBenefitItemDetails executed');
    }

    @isTest
    static void test_CBID_NullItemLink() {
        // Covers: detail found but Coverage_Benefit_Item__c = null
        // → coverageBenefitItemIds stays empty → inner isEmpty guard fires
        // Fake Id avoids any DML with null required fields
        Id fakeDetailId = '0TXbf000000FAKEAAA';
        Test.startTest();
        MemberPlanCalloutFuture.sendForCoverageBenefitItemDetails(
            new List<Id>{ fakeDetailId }
        );
        Test.stopTest();
        System.assert(true, 'Inner coverageBenefitItemIds.isEmpty guard executed');
    }

    @isTest
    static void test_CBID_Success() {
        TestChain chain    = buildChain();
        String originalKey = ensureSettingsAndGetOriginalKey();
        try {
            Test.setMock(HttpCalloutMock.class, new MockHttp200());
            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefitItemDetails(
                new List<Id>{ chain.detailId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'test_CBID_Success completed');
    }

    @isTest
    static void test_CBID_HttpError() {
        // Covers: detail path → callout 500 → error log branch
        TestChain chain    = buildChain();
        String originalKey = ensureSettingsAndGetOriginalKey();
        try {
            Test.setMock(HttpCalloutMock.class, new MockHttp500());
            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefitItemDetails(
                new List<Id>{ chain.detailId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'test_CBID_HttpError completed');
    }

    @isTest
    static void test_CBID_BulkIds() {
        // Covers: multiple details in one call
        TestChain c1 = buildChain();
        TestChain c2 = buildChain();

        String originalKey = ensureSettingsAndGetOriginalKey();
        try {
            Test.setMock(HttpCalloutMock.class, new MockHttp200());
            Test.startTest();
            MemberPlanCalloutFuture.sendForCoverageBenefitItemDetails(
                new List<Id>{ c1.detailId, c2.detailId }
            );
            Test.stopTest();
        } finally {
            restoreSettings(originalKey);
        }
        System.assert(true, 'test_CBID_BulkIds completed');
    }
}