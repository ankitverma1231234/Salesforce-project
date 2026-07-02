@IsTest(SeeAllData=true)
private class MemberAccessApprovalControllerTest {
    
    private static Account getOrCreatePersonAccount(String first, String last, String email) {
        List<Account> existing = [
            SELECT Id, Name, FirstName, LastName, PersonEmail
            FROM   Account
            WHERE  IsPersonAccount = true
            AND    PersonEmail     = :email
            LIMIT  1
        ];
        if (!existing.isEmpty()) return existing[0];
        
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
        
        // ✅ Added Name to re-query
        return [
            SELECT Id, Name, FirstName, LastName, PersonEmail 
            FROM   Account 
            WHERE  Id = :acc.Id
        ];
    }
    
    // ─── Helper: build fixture ─────────────────────────────────────────────
    private static Account_head_relationship__c buildFixture() {
        Account authorized = getOrCreatePersonAccount('Jane',   'Authorized', 'jane.member.test@example.com');
        Account member     = getOrCreatePersonAccount('Daniel', 'Member',     'daniel.member.test@example.com');
        
        Account_head_relationship__c rel = new Account_head_relationship__c(
            Authorized_Account_Access__c = authorized.Id,
            Member_Account__c            = member.Id
        );
        insert rel;
        
        return [
            SELECT Id, 
            Approval_Token__c, 
            Verification_Code__c,
            Portal_Access_Status__c, 
            Token_Expiry__c,
            Member_Account__r.Name,
            Authorized_Account_Access__r.Name
            FROM   Account_head_relationship__c
            WHERE  Id = :rel.Id
        ];
    }
    
    // ─── Test 1: validateMemberToken returns correct TokenInfo ────────────
    @IsTest
    static void validateTokenReturnsInfo() {
        Account_head_relationship__c rel = buildFixture();
        
        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped by trigger');
        
        MemberAccessApprovalController.TokenInfo info =
            MemberAccessApprovalController.validateMemberToken(rel.Approval_Token__c);
        
        System.assertEquals('Pending', info.status,           'Status should be Pending');
        System.assertEquals(false,     info.expired,          'Token should not be expired');
        System.assertEquals(false,     info.alreadyProcessed, 'Should not be processed yet');
        System.assertNotEquals('',     info.authorizedFullName,'Full name should be populated');
    }
    
    // ─── Test 2: invalid token throws ─────────────────────────────────────
    @IsTest
    static void validateTokenInvalidThrows() {
        try {
            MemberAccessApprovalController.validateMemberToken('not-a-real-token');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            // expected
        }
    }
    
    // ─── Test 3: approve ──────────────────────────────────────────────────
    @IsTest
    static void processActionApproves() {
        Account_head_relationship__c rel = buildFixture();
        
        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped by trigger');
        
        Test.startTest();
        MemberAccessApprovalController.ApprovalResult res =
            MemberAccessApprovalController.processMemberAction(
                rel.Approval_Token__c, 'approve', rel.Verification_Code__c);
        Test.stopTest();
        
        System.assertEquals(true,       res.success, 'Should succeed');
        System.assertEquals('Approved', res.status,  'Status should be Approved');
        
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
    static void processActionRejects() {
        Account_head_relationship__c rel = buildFixture();
        
        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped by trigger');
        
        MemberAccessApprovalController.ApprovalResult res =
            MemberAccessApprovalController.processMemberAction(
                rel.Approval_Token__c, 'reject', rel.Verification_Code__c);
        
        System.assertEquals(true,     res.success, 'Should succeed');
        System.assertEquals('Denied', res.status,  'Status should be Denied');
    }
    
    // ─── Test 5: wrong verification code throws ───────────────────────────
    @IsTest
    static void wrongCodeThrows() {
        Account_head_relationship__c rel = buildFixture();
        
        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped by trigger');
        
        try {
            MemberAccessApprovalController.processMemberAction(
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
        
        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped by trigger');
        
        // Backdate expiry to simulate an expired request
        rel.Token_Expiry__c = Datetime.now().addDays(-1);
        update rel;
        
        try {
            MemberAccessApprovalController.processMemberAction(
                rel.Approval_Token__c, 'approve', rel.Verification_Code__c);
            System.assert(false, 'Expected failure on expired token');
        } catch (AuraHandledException e) {
            // expected
        }
    }
    
    // ─── Test 7: replay prevented after approval ──────────────────────────
    @IsTest
    static void replayPreventedAfterApproval() {
        Account_head_relationship__c rel = buildFixture();
        
        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped by trigger');
        
        String originalToken = rel.Approval_Token__c;
        String originalCode  = rel.Verification_Code__c;
        
        // First approval succeeds
        MemberAccessApprovalController.processMemberAction(
            originalToken, 'approve', originalCode);
        
        // Second attempt must fail — token is now null in DB
        try {
            MemberAccessApprovalController.processMemberAction(
                originalToken, 'approve', originalCode);
            System.assert(false, 'Expected failure on replay');
        } catch (AuraHandledException e) {
            // expected
        }
    }
    
    // ─── Test 8: already processed record throws ──────────────────────────
    @IsTest
    static void alreadyProcessedThrows() {
        Account_head_relationship__c rel = buildFixture();
        
        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped by trigger');
        
        // Force status to Approved without clearing token (simulate stale state)
        rel.Portal_Access_Status__c = 'Approved';
        update rel;
        
        try {
            MemberAccessApprovalController.processMemberAction(
                rel.Approval_Token__c, 'approve', rel.Verification_Code__c);
            System.assert(false, 'Expected failure — already processed');
        } catch (AuraHandledException e) {
            // expected
        }
    }
    
    // ─── Test 9: action is case-insensitive ───────────────────────────────
    @IsTest
    static void actionCaseInsensitive() {
        Account_head_relationship__c rel = buildFixture();
        
        System.assertNotEquals(null, rel.Approval_Token__c, 'Token must be stamped by trigger');
        
        MemberAccessApprovalController.ApprovalResult res =
            MemberAccessApprovalController.processMemberAction(
                rel.Approval_Token__c, 'APPROVE', rel.Verification_Code__c);
        
        System.assertEquals(true,       res.success);
        System.assertEquals('Approved', res.status);
    }
    
    // ─── Test 10: missing / null inputs throw ─────────────────────────────
    @IsTest
    static void missingInputsThrow() {
        // validateMemberToken
        try { MemberAccessApprovalController.validateMemberToken(null);
             System.assert(false); } catch (AuraHandledException e) {}
        
        try { MemberAccessApprovalController.validateMemberToken('');
             System.assert(false); } catch (AuraHandledException e) {}
        
        // processMemberAction – missing token
        try { MemberAccessApprovalController.processMemberAction(null, 'approve', '123456');
             System.assert(false); } catch (AuraHandledException e) {}
        
        // processMemberAction – missing action
        try { MemberAccessApprovalController.processMemberAction('tok', null, '123456');
             System.assert(false); } catch (AuraHandledException e) {}
        
        // processMemberAction – missing verification code
        try { MemberAccessApprovalController.processMemberAction('tok', 'approve', null);
             System.assert(false); } catch (AuraHandledException e) {}
        
        // processMemberAction – unsupported action
        try { MemberAccessApprovalController.processMemberAction('tok', 'bogus', '123456');
             System.assert(false); } catch (AuraHandledException e) {}
    }
}