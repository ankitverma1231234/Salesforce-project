@IsTest(seeAllData=true)
public class MemberPlanControllerTest {

    // --------------------------------------------------
    // HTTP CALLOUT MOCK
    // --------------------------------------------------
    private class InsuranceAPIMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }

    // --------------------------------------------------
    // MAIN TEST METHOD
    // --------------------------------------------------
    @IsTest
    static void testWithExistingData() {

        // ----------------------------------------------
        // 1. GET OR CREATE PERSON ACCOUNT (AS REQUESTED)
        // ----------------------------------------------
        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail != null
            AND PersonMobilePhone != null
            LIMIT 1
        ];

        Account acc;
        if (existingAccounts.isEmpty()) {

            Id personAccountRT = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount')
                .getRecordTypeId();

            acc = new Account(
                FirstName = 'Existing',
                LastName  = 'Test',
                RecordTypeId = personAccountRT,
                PersonEmail = 'existing.test@example.com',
                PersonMobilePhone = '5551234567'
            );
            insert acc;

        } else {
            acc = existingAccounts[0];
        }

        // ----------------------------------------------
        // 2. CREATE MEMBER PLAN
        // ----------------------------------------------
        MemberPlan plan = new MemberPlan(
            Name = 'Test Member Plan',
            MemberId = acc.Id,
            MemberNumber = 'MP-001',
            GroupNumber = 'GRP-001',
            EffectiveFrom = Date.today(),
            VerificationStatus = 'Verified'
        );
        insert plan;

        // ----------------------------------------------
        // 3. CREATE COVERAGE BENEFIT
        // ----------------------------------------------
        CoverageBenefit benefit = new CoverageBenefit(
            Name = 'Test Coverage Benefit',
            MemberId = acc.Id,
            MemberPlanId = plan.Id,
            InNetworkCoinsuranceAmount = 20,
            OutofNetworkCoinsuranceAmount = 40
        );
        insert benefit;

        // ----------------------------------------------
        // 4. CREATE COVERAGE BENEFIT ITEM
        // ----------------------------------------------
        CoverageBenefitItem item = new CoverageBenefitItem(
            Name = 'Test Benefit Item',
            MemberId = acc.Id,
            CoverageBenefitId = benefit.Id
        );
        insert item;

        // ----------------------------------------------
        // 5. CREATE COVERAGE BENEFIT ITEM DETAIL
        // ----------------------------------------------
        medicalcoverage__CoverageBenefitItemDetail__c detail =
            new medicalcoverage__CoverageBenefitItemDetail__c(
                medicalcoverage__Coverage_Benefit_Item__c = item.Id,
                medicalcoverage__Cateogy__c = 'Deductible',
                medicalcoverage__remainingAmount__c = 500
            );
        insert detail;

        // ----------------------------------------------
        // 6. CREATE CUSTOM SETTING (IF NOT PRESENT)
        // ----------------------------------------------
        BatonPortalAPI__c setting = BatonPortalAPI__c.getOrgDefaults();
        if (setting == null) {
            setting = new BatonPortalAPI__c(
                Insurance_Key__c = 'https://test.endpoint.com/api'
            );
            insert setting;
        }
        Test.setMock(HttpCalloutMock.class, new InsuranceAPIMock());

        Test.startTest();
        String result = MemberPlanController.sendAllMemberPlansToThirdParty(acc.Id);
        Test.stopTest();

        // ----------------------------------------------
        // 8. ASSERTIONS
        // ----------------------------------------------
        System.assert(result.contains('Success'),
            'Expected success response from API callout');
    }
}