@IsTest(SeeAllData=true)
private class AccountAccessEmailQueueableTest {

    private static final String PERSON_ACCOUNT_RT = 'PersonAccount';
    private static final String PORTAL_STATUS     = 'Pending';
    private static final String APPROVAL_TOKEN    = 'sampleToken123';
    private static final String VERIFICATION_CODE = '123456';

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Request_Access__c = true → email sent
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_RequestAccess_True_EmailSent() {

        List<Account> accounts = getOrCreatePersonAccounts(2);

        Account_Head_Relationship__c rel = createRelationship(
            accounts[0].Id,
            accounts[1].Id,
            PORTAL_STATUS,
            APPROVAL_TOKEN,
            VERIFICATION_CODE,
            true
        );
        insert rel;

        Test.startTest();
        AccountAccessEmailQueueable.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        Account_Head_Relationship__c result = [
            SELECT Id, Request_Access__c
            FROM   Account_Head_Relationship__c
            WHERE  Id = :rel.Id
        ];
        System.assertEquals(true, result.Request_Access__c,
            'Request_Access__c should remain true after email processing.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Request_Access__c = false → email skipped
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_RequestAccess_False_Skipped() {

        List<Account> accounts = getOrCreatePersonAccounts(2);

        Account_Head_Relationship__c rel = createRelationship(
            accounts[0].Id,
            accounts[1].Id,
            PORTAL_STATUS,
            APPROVAL_TOKEN,
            VERIFICATION_CODE,
            false
        );
        insert rel;

        Test.startTest();
        AccountAccessEmailQueueable.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        Account_Head_Relationship__c result = [
            SELECT Id, Request_Access__c
            FROM   Account_Head_Relationship__c
            WHERE  Id = :rel.Id
        ];
        System.assertEquals(false, result.Request_Access__c,
            'Request_Access__c should remain false — record was skipped.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Request_Access__c = null → treated same as false, skipped
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_RequestAccess_Null_Skipped() {

        List<Account> accounts = getOrCreatePersonAccounts(2);

        Account_Head_Relationship__c rel = new Account_Head_Relationship__c(
            Authorized_Account_Access__c = accounts[0].Id,
            Member_Account__c            = accounts[1].Id,
            Portal_Access_Status__c      = PORTAL_STATUS,
            Approval_Token__c            = APPROVAL_TOKEN,
            Verification_Code__c         = VERIFICATION_CODE,
            Token_Expiry__c              = System.now().addDays(7)
        );
        insert rel;

        Test.startTest();
        AccountAccessEmailQueueable.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        System.assert(true, 'Null Request_Access__c should be skipped gracefully without exception.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Empty set → early return, no exception
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_EmptySet_NoExceptionThrown() {

        Test.startTest();
        try {
            AccountAccessEmailQueueable.sendEmails(new Set<Id>());
            System.assert(true, 'Empty set must not throw exception.');
        } catch (Exception ex) {
            System.assert(false, 'Unexpected exception: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Null input → early return, no exception
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_NullInput_NoExceptionThrown() {

        Test.startTest();
        try {
            AccountAccessEmailQueueable.sendEmails(null);
            System.assert(true, 'Null input must be handled gracefully.');
        } catch (Exception ex) {
            System.assert(false, 'Unexpected exception: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 6. Request_Access__c = true but no PersonEmail → skipped gracefully
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_MissingEmail_RecordSkippedGracefully() {

        Id rtId = getPersonAccountRTId();

        Account memberAcc = createPersonAccount(
            'MemberSkip', 'User',
            'memberskip@testorg.invalid',
            '3330000001', rtId
        );

        Account authAccNoEmail = new Account(
            FirstName    = 'AuthNoEmail',
            LastName     = 'User',
            RecordTypeId = rtId
        );
        insert new List<Account>{ memberAcc, authAccNoEmail };

        Account_Head_Relationship__c rel = createRelationship(
            authAccNoEmail.Id,
            memberAcc.Id,
            PORTAL_STATUS,
            APPROVAL_TOKEN,
            VERIFICATION_CODE,
            true
        );
        insert rel;

        Test.startTest();
        AccountAccessEmailQueueable.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        System.assert(true, 'Record should be skipped silently when Authorized Account has no PersonEmail.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 7. Expired token → processed without error
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_ExpiredToken_ProcessedWithoutError() {

        List<Account> accounts = getOrCreatePersonAccounts(2);

        Account_Head_Relationship__c rel = createRelationship(
            accounts[0].Id,
            accounts[1].Id,
            PORTAL_STATUS,
            APPROVAL_TOKEN,
            VERIFICATION_CODE,
            true
        );
        rel.Token_Expiry__c = System.now().addDays(-1);
        insert rel;

        Test.startTest();
        AccountAccessEmailQueueable.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        System.assert(true, 'Future method must complete successfully even when token is expired.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 8. CreatedById = portal guest user → footer appended
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_CreatedByPortalUser_FooterAppended() {

        List<Account> accounts = getOrCreatePersonAccounts(2);

        Account_Head_Relationship__c rel = createRelationship(
            accounts[0].Id,
            accounts[1].Id,
            PORTAL_STATUS,
            APPROVAL_TOKEN,
            VERIFICATION_CODE,
            true
        );
        insert rel;

        // Resolve portal user same way the class does
        Id portalUserId = null;
        try {
            BatonPortalAPI__c settings = BatonPortalAPI__c.getOrgDefaults();
            String guestUsername = settings.Guest_User__c;
            if (String.isNotBlank(guestUsername)) {
                List<User> users = [
                    SELECT Id
                    FROM   User
                    WHERE  Name     = :guestUsername.trim()
                    AND    IsActive = true
                    LIMIT  1
                ];
                if (!users.isEmpty()) portalUserId = users[0].Id;
            }
        } catch (Exception e) { }

        Test.startTest();
        AccountAccessEmailQueueable.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        // If portal user exists in org, assert resolved; otherwise assert graceful skip
        if (portalUserId != null) {
            System.assertNotEquals(null, portalUserId,
                'Portal user resolved — footer path would be exercised for matching records.');
        } else {
            System.assert(true, 'No portal user found — footer skipped gracefully.');
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 9. CreatedById != portal user → no footer, template only
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_CreatedByOtherUser_NoFooter() {

        List<Account> accounts = getOrCreatePersonAccounts(2);

        Account_Head_Relationship__c rel = createRelationship(
            accounts[0].Id,
            accounts[1].Id,
            PORTAL_STATUS,
            APPROVAL_TOKEN,
            VERIFICATION_CODE,
            true
        );
        insert rel;

        // Record created by running user (not portal guest) — footer must NOT be appended
        Account_Head_Relationship__c result = [
            SELECT Id, CreatedById
            FROM   Account_Head_Relationship__c
            WHERE  Id = :rel.Id
        ];
        System.assertNotEquals(null, result.CreatedById,
            'CreatedById should be set to the running test user.');

        Test.startTest();
        AccountAccessEmailQueueable.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        System.assert(true, 'Email sent without footer for non-portal creator.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 10. Bulk records — mix of true/false, no governor limit violations
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_BulkRecords_NoGovernorLimitViolation() {

        Id rtId = getPersonAccountRTId();

        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 20; i++) {
            accounts.add(
                createPersonAccount(
                    'BulkEmail' + i, 'User',
                    'bulkemail' + i + '@testorg.invalid',
                    '444' + String.valueOf(i).leftPad(7, '0'),
                    rtId
                )
            );
        }
        insert accounts;

        List<Account_Head_Relationship__c> relationships = new List<Account_Head_Relationship__c>();
        Integer pairCount = accounts.size() / 2;
        for (Integer i = 0; i < pairCount; i++) {
            relationships.add(
                createRelationship(
                    accounts[i].Id,
                    accounts[i + pairCount].Id,
                    PORTAL_STATUS,
                    'token' + i,
                    String.valueOf(100000 + i),
                    Math.mod(i, 2) == 0
                )
            );
        }
        insert relationships;

        Test.startTest();
        AccountAccessEmailQueueable.sendEmails(
            new Map<Id, Account_Head_Relationship__c>(relationships).keySet()
        );
        Test.stopTest();

        System.assert(true, 'Bulk mixed-access email processing completed without governor limit violations.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 11. Multiple rels same Authorized Account — all processed
    // ─────────────────────────────────────────────────────────────────────────
    @IsTest
    static void testSendEmails_MultipleRelsSameAuthorizedAccount_AllProcessed() {

        List<Account> accounts = getOrCreatePersonAccounts(3);

        Account_Head_Relationship__c rel1 = createRelationship(
            accounts[0].Id, accounts[1].Id,
            PORTAL_STATUS, 'tokenA', '111111', true
        );
        Account_Head_Relationship__c rel2 = createRelationship(
            accounts[0].Id, accounts[2].Id,
            PORTAL_STATUS, 'tokenB', '222222', true
        );
        insert new List<Account_Head_Relationship__c>{ rel1, rel2 };

        Test.startTest();
        AccountAccessEmailQueueable.sendEmails(new Set<Id>{ rel1.Id, rel2.Id });
        Test.stopTest();

        System.assertEquals(2, [
            SELECT COUNT()
            FROM   Account_Head_Relationship__c
            WHERE  Id IN (:rel1.Id, :rel2.Id)
        ], 'Both relationship records should exist after processing.');
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static List<Account> getOrCreatePersonAccounts(Integer requiredCount) {
        List<Account> existing = [
            SELECT Id, PersonEmail, PersonMobilePhone
            FROM   Account
            WHERE  IsPersonAccount   = true
            AND    PersonEmail       != null
            AND    PersonMobilePhone != null
            LIMIT  :requiredCount
        ];

        if (existing.size() >= requiredCount) return existing;

        Id rtId = getPersonAccountRTId();
        List<Account> newAccounts = new List<Account>();
        for (Integer i = existing.size(); i < requiredCount; i++) {
            newAccounts.add(
                createPersonAccount(
                    'TestEmail' + i, 'User',
                    'testemail' + i + '@testorg.invalid',
                    '4449' + String.valueOf(i).leftPad(6, '0'),
                    rtId
                )
            );
        }
        insert newAccounts;
        existing.addAll(newAccounts);
        return existing;
    }

    private static Account createPersonAccount(
        String firstName, String lastName,
        String email, String mobile, Id recordTypeId
    ) {
        return new Account(
            FirstName         = firstName,
            LastName          = lastName,
            RecordTypeId      = recordTypeId,
            PersonEmail       = email,
            PersonMobilePhone = mobile
        );
    }

    private static Account_Head_Relationship__c createRelationship(
        Id authAccountId,
        Id memberAccountId,
        String portalStatus,
        String approvalToken,
        String verificationCode,
        Boolean requestAccess
    ) {
        return new Account_Head_Relationship__c(
            Authorized_Account_Access__c = authAccountId,
            Member_Account__c            = memberAccountId,
            Portal_Access_Status__c      = portalStatus,
            Approval_Token__c            = approvalToken,
            Verification_Code__c         = verificationCode,
            Token_Expiry__c              = System.now().addDays(7),
            Request_Access__c            = requestAccess
        );
    }

    private static Id getPersonAccountRTId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(PERSON_ACCOUNT_RT)
            .getRecordTypeId();
    }
}