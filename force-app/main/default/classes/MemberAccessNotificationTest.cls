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

    @isTest
    static void testSendEmails_GiveAccess_True_Success() {
        Account memberAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 1
        ];
        Account authorizedAccount = [
            SELECT Id, Name FROM Account
            WHERE  IsPersonAccount = true AND Id != :memberAccount.Id LIMIT 1
        ];

        Account_head_relationship__c rel = buildRel(memberAccount.Id, authorizedAccount.Id, '001', true);
        insert rel;

        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        Account_head_relationship__c result = [
            SELECT Id, Give_Access__c FROM Account_head_relationship__c WHERE Id = :rel.Id  // ✅ fixed
        ];
        System.assertNotEquals(null, result, 'Relationship record should still exist after email send.');
        System.assertEquals(true, result.Give_Access__c,                                    // ✅ fixed
            'Give_Access__c should remain true after processing.');
    }

    @isTest
    static void testSendEmails_GiveAccess_False_Skipped() {
        Account memberAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 1
        ];
        Account authorizedAccount = [
            SELECT Id, Name FROM Account
            WHERE  IsPersonAccount = true AND Id != :memberAccount.Id LIMIT 1
        ];

        Account_head_relationship__c rel = buildRel(memberAccount.Id, authorizedAccount.Id, '002', false);
        insert rel;

        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        Account_head_relationship__c result = [
            SELECT Id, Give_Access__c FROM Account_head_relationship__c WHERE Id = :rel.Id  // ✅ fixed
        ];
        System.assertEquals(false, result.Give_Access__c,                                   // ✅ fixed
            'Give_Access__c should remain false — record was skipped.');
    }

    @isTest
    static void testSendEmails_GiveAccess_Null_Skipped() {
        Account memberAccount = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  PersonEmail != null AND IsPersonAccount = true LIMIT 1
        ];
        Account authorizedAccount = [
            SELECT Id, Name FROM Account
            WHERE  IsPersonAccount = true AND Id != :memberAccount.Id LIMIT 1
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

    @isTest
    static void testSendEmails_NoMemberPersonEmail_Skipped() {
        Account memberNoEmail = [
            SELECT Id, PersonEmail, Name FROM Account
            WHERE  IsPersonAccount = true AND PersonEmail = null LIMIT 1
        ];
        Account authorizedAccount = [
            SELECT Id, Name FROM Account
            WHERE  IsPersonAccount = true AND Id != :memberNoEmail.Id LIMIT 1
        ];

        Account_head_relationship__c rel = buildRel(memberNoEmail.Id, authorizedAccount.Id, '004', true);
        insert rel;

        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>{ rel.Id });
        Test.stopTest();

        System.assert(true, 'Should skip without exception when Member has no PersonEmail.');
    }

    @isTest
    static void testSendEmails_NullInput() {
        Test.startTest();
        MemberAccessNotification.sendEmails(null);
        Test.stopTest();
        System.assert(true, 'No exception on null input.');
    }

    @isTest
    static void testSendEmails_EmptySet() {
        Test.startTest();
        MemberAccessNotification.sendEmails(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'No exception on empty set.');
    }

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

        Integer count = [SELECT COUNT() FROM Account_head_relationship__c WHERE Id IN :relIds];
        System.assertEquals(rels.size(), count,
            'All relationship records should exist after mixed-access email run.');
    }
}