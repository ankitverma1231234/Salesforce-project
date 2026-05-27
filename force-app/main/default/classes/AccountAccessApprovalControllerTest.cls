@IsTest(SeeAllData=true)
private class AccountAccessApprovalControllerTest {

    // ─── Helper: get or create Person Account ─────────────────────────────
    private static Account getOrCreatePersonAccount(String first, String last, String email) {
        List<Account> existing = [
            SELECT Id, FirstName, LastName, PersonEmail
            FROM   Account
            WHERE  IsPersonAccount = true
            AND    PersonEmail = :email
            LIMIT  1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        Id personAccountRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account acc = new Account(
            FirstName    = first,
            LastName     = last,
            RecordTypeId = personAccountRTId,
            PersonEmail  = email
        );
        insert acc;
        return [SELECT Id, FirstName, LastName, PersonEmail FROM Account WHERE Id = :acc.Id];
    }

    // ─── Helper: build fixture ─────────────────────────────────────────────
    private static Account_head_relationship__c buildFixture() {
        Account member    = getOrCreatePersonAccount('Mary', 'Member',    'mary.ctrl.test@example.com');
        Account requestor = getOrCreatePersonAccount('Rob',  'Requestor', 'rob.ctrl.test@example.com');

        Account_head_relationship__c rel = new Account_head_relationship__c(
            Member_Account__c            = member.Id,
            Authorized_Account_Access__c = requestor.Id
        );
        insert rel;

        return [
            SELECT Id, Approval_Token__c, Verification_Code__c,
                   Portal_Access_Status__c, Token_Expiry__c
            FROM   Account_head_relationship__c
            WHERE  Id = :rel.Id
        ];
    }

    // ─── Test 1: validateToken returns correct info ────────────────────────
    @IsTest
    static void validateTokenReturnsInfo() {
        Account_head_relationship__c rel = buildFixture();

        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped by trigger');

        AccountAccessApprovalController.TokenInfo info =
            AccountAccessApprovalController.validateToken(rel.Approval_Token__c);

        System.assertEquals('Pending',       info.status);
        System.assertEquals(false,           info.expired);
        System.assertEquals(false,           info.alreadyProcessed);
    }

    // ─── Test 2: invalid token throws ─────────────────────────────────────
    @IsTest
    static void validateTokenInvalidThrows() {
        try {
            AccountAccessApprovalController.validateToken('not-a-real-token');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            // expected
        }
    }

    // ─── Test 3: approve ──────────────────────────────────────────────────
    @IsTest
    static void processApprovalApproves() {
        Account_head_relationship__c rel = buildFixture();

        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped');

        Test.startTest();
        AccountAccessApprovalController.ApprovalResult res =
            AccountAccessApprovalController.processApproval(
                rel.Approval_Token__c, 'approve', rel.Verification_Code__c);
        Test.stopTest();

        System.assertEquals(true,       res.success);
        System.assertEquals('Approved', res.status);

        Account_head_relationship__c after = [
            SELECT Portal_Access_Status__c, Approval_Token__c
            FROM   Account_head_relationship__c
            WHERE  Id = :rel.Id
        ];
        System.assertEquals('Approved', after.Portal_Access_Status__c);
        System.assertEquals(null,       after.Approval_Token__c, 'Token should be cleared');
    }

    // ─── Test 4: reject ───────────────────────────────────────────────────
    @IsTest
    static void processApprovalRejects() {
        Account_head_relationship__c rel = buildFixture();

        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped');

        AccountAccessApprovalController.ApprovalResult res =
            AccountAccessApprovalController.processApproval(
                rel.Approval_Token__c, 'reject', rel.Verification_Code__c);

        System.assertEquals('Denied', res.status);
    }

    // ─── Test 5: wrong code throws ────────────────────────────────────────
    @IsTest
    static void wrongCodeThrows() {
        Account_head_relationship__c rel = buildFixture();

        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped');

        try {
            AccountAccessApprovalController.processApproval(
                rel.Approval_Token__c, 'approve', '000000');
            System.assert(false, 'Expected failure on wrong code');
        } catch (AuraHandledException e) {
            // expected
        }
    }

    // ─── Test 6: expired token throws ─────────────────────────────────────
    @IsTest
    static void expiredTokenThrows() {
        Account_head_relationship__c rel = buildFixture();

        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped');

        // Backdate expiry
        rel.Token_Expiry__c = Datetime.now().addDays(-1);
        update rel;

        try {
            AccountAccessApprovalController.processApproval(
                rel.Approval_Token__c, 'approve', rel.Verification_Code__c);
            System.assert(false, 'Expected failure on expired token');
        } catch (AuraHandledException e) {
            // expected
        }
    }

    // ─── Test 7: replay prevented after approval ───────────────────────────
    @IsTest
    static void replayPreventedAfterApproval() {
        Account_head_relationship__c rel = buildFixture();

        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped');

        // First approval succeeds
        AccountAccessApprovalController.processApproval(
            rel.Approval_Token__c, 'approve', rel.Verification_Code__c);

        // Second attempt should fail — token is now null
        try {
            AccountAccessApprovalController.processApproval(
                rel.Approval_Token__c, 'approve', rel.Verification_Code__c);
            System.assert(false, 'Expected failure on replay');
        } catch (AuraHandledException e) {
            // expected
        }
    }

    // ─── Test 8: missing inputs throw ────────────────────────────────────
    @IsTest
    static void missingInputsThrow() {
        try { AccountAccessApprovalController.validateToken(null);
              System.assert(false); } catch (AuraHandledException e) {}

        try { AccountAccessApprovalController.processApproval(null, 'approve', '123456');
              System.assert(false); } catch (AuraHandledException e) {}

        try { AccountAccessApprovalController.processApproval('x', null, '123456');
              System.assert(false); } catch (AuraHandledException e) {}

        try { AccountAccessApprovalController.processApproval('x', 'approve', null);
              System.assert(false); } catch (AuraHandledException e) {}

        try { AccountAccessApprovalController.processApproval('x', 'bogus', '123456');
              System.assert(false); } catch (AuraHandledException e) {}
    }
}