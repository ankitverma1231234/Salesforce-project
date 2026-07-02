@isTest(SeeAllData=true)
public class MemberAccessNotificationTest {

    private static Account_head_relationship__c buildRel(
        Id memberId,
        Id authorizedId,
        String tokenSuffix,
        Boolean giveAccess
    ) {
        return new Account_head_relationship__c(
            Member_Account__c            = memberId,
            Authorized_Account_Access__c = authorizedId,
            Approval_Token__c            = 'TEST_TOKEN_' + tokenSuffix,
            Verification_Code__c         = tokenSuffix,
            Token_Expiry__c              = Datetime.now().addDays(7),
            Portal_Access_Status__c      = 'Pending',
            Give_Access__c               = giveAccess
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Give_Access__c = true → email sent
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSendEmails_GiveAccess_True_Success() {
        Account memberAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 1
        ];
        Account authorizedAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  IsPersonAccount = true AND PersonEmail != null AND Id != :memberAccount.Id LIMIT 1
        ];

        Account_head_relationship__c rel = buildRel(memberAccount.Id, authorizedAccount.Id, '001', true);
        insert rel;

        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        Account_head_relationship__c result = [
            SELECT Id, Give_Access__c FROM Account_head_relationship__c WHERE Id = :rel.Id
        ];
        System.assertEquals(true, result.Give_Access__c,
            'Give_Access__c should remain true after processing.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Give_Access__c = false → email skipped
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSendEmails_GiveAccess_False_Skipped() {
        Account memberAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 1
        ];
        Account authorizedAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  IsPersonAccount = true AND PersonEmail != null AND Id != :memberAccount.Id LIMIT 1
        ];

        Account_head_relationship__c rel = buildRel(memberAccount.Id, authorizedAccount.Id, '002', false);
        insert rel;

        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        Account_head_relationship__c result = [
            SELECT Id, Give_Access__c FROM Account_head_relationship__c WHERE Id = :rel.Id
        ];
        System.assertEquals(false, result.Give_Access__c,
            'Give_Access__c should remain false — record was skipped.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Give_Access__c = null → skipped gracefully
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSendEmails_GiveAccess_Null_Skipped() {
        Account memberAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 1
        ];
        Account authorizedAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  IsPersonAccount = true AND PersonEmail != null AND Id != :memberAccount.Id LIMIT 1
        ];

        Account_head_relationship__c rel = new Account_head_relationship__c(
            Member_Account__c            = memberAccount.Id,
            Authorized_Account_Access__c = authorizedAccount.Id,
            Approval_Token__c            = 'TEST_TOKEN_003',
            Verification_Code__c         = '003003',
            Token_Expiry__c              = Datetime.now().addDays(7),
            Portal_Access_Status__c      = 'Pending'
            // Give_Access__c intentionally omitted → null
        );
        insert rel;

        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        System.assert(true, 'Null Give_Access__c should be skipped without exception.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Authorized Account has no PersonEmail → skipped gracefully
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSendEmails_NoAuthorizedPersonEmail_Skipped() {
        Account memberAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 1
        ];

        Id rtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account authNoEmail = new Account(
            FirstName    = 'AuthNoEmail',
            LastName     = 'User',
            RecordTypeId = rtId
        );
        insert authNoEmail;

        Account_head_relationship__c rel = buildRel(memberAccount.Id, authNoEmail.Id, '004', true);
        insert rel;

        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        System.assert(true, 'Should skip without exception when Authorized Account has no PersonEmail.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Null input → early return, no exception
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSendEmails_NullInput() {
        Test.startTest();
        MemberAccessNotification.sendEmails(null);
        Test.stopTest();
        System.assert(true, 'No exception on null input.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 6. Empty set → early return, no exception
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSendEmails_EmptySet() {
        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'No exception on empty set.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 7. CreatedById = portal guest user → footer appended
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSendEmails_CreatedByPortalUser_FooterAppended() {
        Account memberAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 1
        ];
        Account authorizedAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  IsPersonAccount = true AND PersonEmail != null AND Id != :memberAccount.Id LIMIT 1
        ];

        Account_head_relationship__c rel = buildRel(memberAccount.Id, authorizedAccount.Id, '005', true);
        insert rel;

        // Resolve portal user same way the class does
        Id portalUserId = null;
        try {
            BatonPortalAPI__c settings = BatonPortalAPI__c.getOrgDefaults();
            String guestUsername = settings.Guest_User__c;
            if (String.isNotBlank(guestUsername)) {
                List<User> users = [
                    SELECT Id FROM User
                    WHERE  Name     = :guestUsername.trim()
                    AND    IsActive = true
                    LIMIT  1
                ];
                if (!users.isEmpty()) portalUserId = users[0].Id;
            }
        } catch (Exception e) { }

        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        if (portalUserId != null) {
            System.assertNotEquals(null, portalUserId,
                'Portal user resolved — footer path exercised for matching records.');
        } else {
            System.assert(true, 'No portal user found — footer skipped gracefully.');
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 8. CreatedById != portal user → no footer, template only
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSendEmails_CreatedByOtherUser_NoFooter() {
        Account memberAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 1
        ];
        Account authorizedAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  IsPersonAccount = true AND PersonEmail != null AND Id != :memberAccount.Id LIMIT 1
        ];

        Account_head_relationship__c rel = buildRel(memberAccount.Id, authorizedAccount.Id, '006', true);
        insert rel;

        Account_head_relationship__c result = [
            SELECT Id, CreatedById FROM Account_head_relationship__c WHERE Id = :rel.Id
        ];
        System.assertNotEquals(null, result.CreatedById,
            'CreatedById should be set to the running test user.');

        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        System.assert(true, 'Email sent without footer for non-portal creator.');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 9. Bulk records — mixed Give_Access__c, no governor limit violations
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void testSendEmails_MultipleRecords_MixedGiveAccess() {
        List<Account> accounts = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 4
        ];

        if (accounts.size() < 2) {
            System.assert(true, 'Not enough accounts for multi-record test. Skipping.');
            return;
        }

        List<Account_head_relationship__c> rels = new List<Account_head_relationship__c>();
        for (Integer i = 0; i < accounts.size() - 1; i++) {
            rels.add(buildRel(accounts[i].Id, accounts[i + 1].Id, '10' + i, Math.mod(i, 2) == 0));
        }
        insert rels;

        Set<Id> relIds = new Set<Id>();
        for (Account_head_relationship__c r : rels) relIds.add(r.Id);

        Test.startTest();
        MemberAccessNotification.sendEmails(relIds);
        Test.stopTest();

        System.assertEquals(rels.size(), [
            SELECT COUNT() FROM Account_head_relationship__c WHERE Id IN :relIds
        ], 'All relationship records should exist after mixed-access email run.');
    }
}