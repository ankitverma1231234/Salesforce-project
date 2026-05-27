@IsTest(SeeAllData=true)
private class AccountHeadRelationshipSmsQueueableTest {

    private static final String PORTAL_STATUS     = 'Pending';
    private static final String APPROVAL_TOKEN    = 'sampleToken123';
    private static final String VERIFICATION_CODE = '123456';
    private static final String SMS_TEMPLATE      =
        'Hello {RequestorName}, Code: {VerificationCode}, ' +
        'Approve: {ApproveUrl}, Reject: {DenyUrl}, Expiry: {Expiry}';

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Fetches two existing PersonAccounts from the org that have
     * both PersonEmail and PersonMobilePhone populated.
     */
    private static List<Account> getTwoPersonAccounts() {
        List<Account> accounts = [
            SELECT Id, Name, PersonEmail, PersonMobilePhone
            FROM   Account
            WHERE  IsPersonAccount    = true
            AND    PersonMobilePhone != null
            AND    PersonEmail       != null
            LIMIT  2
        ];
        System.assert(
            accounts.size() >= 2,
            'Org must have at least 2 PersonAccounts with email and mobile for these tests to run.'
        );
        return accounts;
    }

    /**
     * Authorized_Account_Access__c = the child/authorized account → receives the SMS
     * Member_Account__c            = the parent/head account      → requestor name in SMS
     * Request_Access__c must be true — required by the SOQL filter in sendSms()
     */
    private static Account_Head_Relationship__c createRelationship(
        Id    authorizedAccountId,
        Id    memberAccountId,
        String portalStatus,
        String approvalToken,
        String verificationCode
    ) {
        return new Account_Head_Relationship__c(
            Authorized_Account_Access__c = authorizedAccountId,
            Member_Account__c            = memberAccountId,
            Portal_Access_Status__c      = portalStatus,
            Approval_Token__c            = approvalToken,
            Verification_Code__c         = verificationCode,
            Token_Expiry__c              = System.now().addDays(7),
            Request_Access__c            = true
        );
    }

    private static List<sra__Message_History__c> fetchSmsForRelationship(Id relId) {
        return [
            SELECT Id,
                   sra__Receiver_Number__c,
                   sra__Sender_Number__c,
                   sra__Message_Body__c,
                   Account_Head_Relationship__c
            FROM   sra__Message_History__c
            WHERE  Account_Head_Relationship__c = :relId
        ];
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    @IsTest
    static void testQueueable_SingleRecord_SmsShouldBeCreated() {

        List<Account> accounts       = getTwoPersonAccounts();
        Account       authorizedAcct = accounts[0]; // receives SMS
        Account       memberAcct     = accounts[1]; // head/requestor

        Account_Head_Relationship__c rel = createRelationship(
            authorizedAcct.Id,
            memberAcct.Id,
            PORTAL_STATUS,
            APPROVAL_TOKEN,
            VERIFICATION_CODE
        );
        insert rel;

        Test.startTest();
        AccountHeadRelationshipSmsQueueable.sendSms(new Set<Id>{ rel.Id });
        Test.stopTest();

        List<sra__Message_History__c> smsList = fetchSmsForRelationship(rel.Id);

        System.assert(
            !smsList.isEmpty(),
            'Expected at least one SMS record to be created.'
        );
        System.assertEquals(
            rel.Id,
            smsList[0].Account_Head_Relationship__c,
            'SMS must be linked to the correct relationship record.'
        );
    }

    @IsTest
    static void testQueueable_BulkRecords_NoGovernorLimitViolation() {

        // Fetch up to 20 eligible PersonAccounts from the org
        List<Account> accounts = [
            SELECT Id, PersonEmail, PersonMobilePhone
            FROM   Account
            WHERE  IsPersonAccount    = true
            AND    PersonMobilePhone != null
            AND    PersonEmail       != null
            LIMIT  20
        ];

        System.assert(
            accounts.size() >= 2,
            'Org must have at least 2 eligible PersonAccounts for bulk test.'
        );

        // Build as many pairs as possible (up to 10)
        Integer pairCount = (Integer) Math.floor(accounts.size() / 2);

        List<Account_Head_Relationship__c> relationships =
            new List<Account_Head_Relationship__c>();

        for (Integer i = 0; i < pairCount; i++) {
            relationships.add(
                createRelationship(
                    accounts[i].Id,
                    accounts[i + pairCount].Id,
                    PORTAL_STATUS,
                    'bulktoken' + i,
                    String.valueOf(100000 + i)
                )
            );
        }
        insert relationships;

        Set<Id> relIds =
            new Map<Id, Account_Head_Relationship__c>(relationships).keySet();

        Test.startTest();
        AccountHeadRelationshipSmsQueueable.sendSms(relIds);
        Test.stopTest();

        List<sra__Message_History__c> smsList = [
            SELECT Id
            FROM   sra__Message_History__c
            WHERE  Account_Head_Relationship__c IN :relIds
        ];

        System.assertEquals(
            pairCount,
            smsList.size(),
            'Expected one SMS per relationship pair.'
        );
    }

    @IsTest
    static void testQueueable_EmptySet_NoExceptionThrown() {

        Test.startTest();
        try {
            AccountHeadRelationshipSmsQueueable.sendSms(new Set<Id>());
            System.assert(true, 'Queueable with empty set must not throw exception.');
        } catch (Exception ex) {
            System.assert(false, 'Unexpected exception: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testQueueable_NullInput_NoExceptionThrown() {

        Test.startTest();
        try {
            AccountHeadRelationshipSmsQueueable.sendSms(null);
            System.assert(true, 'Null input must be handled gracefully.');
        } catch (Exception ex) {
            System.assert(false, 'Unexpected exception: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testQueueable_ExpiredToken_SmsStillCreated() {

        List<Account> accounts       = getTwoPersonAccounts();
        Account       authorizedAcct = accounts[0];
        Account       memberAcct     = accounts[1];

        Account_Head_Relationship__c rel = createRelationship(
            authorizedAcct.Id,
            memberAcct.Id,
            PORTAL_STATUS,
            APPROVAL_TOKEN,
            VERIFICATION_CODE
        );
        rel.Token_Expiry__c = System.now().addDays(-1); // expired — but not filtered by SOQL
        insert rel;

        Test.startTest();
        AccountHeadRelationshipSmsQueueable.sendSms(new Set<Id>{ rel.Id });
        Test.stopTest();

        List<sra__Message_History__c> smsList = fetchSmsForRelationship(rel.Id);
        System.assert(
            !smsList.isEmpty(),
            'SMS should still be created even when the token is expired.'
        );
    }

    @IsTest
    static void testBuildSmsBody_AllPlaceholders_ReplacedCorrectly() {

        // Use an existing PersonAccount as the member (head) account
        Account memberAcct = [
            SELECT Id, Name
            FROM   Account
            WHERE  IsPersonAccount = true
            LIMIT  1
        ];

        Account_Head_Relationship__c rel = new Account_Head_Relationship__c(
            Approval_Token__c    = 'abc123',
            Verification_Code__c = '654321',
            Token_Expiry__c      = System.now().addDays(7),
            Member_Account__r    = memberAcct
        );

        String result = AccountHeadRelationshipSmsQueueable.buildSmsBody(
            rel,
            SMS_TEMPLATE
        );

        System.assertNotEquals(null,  result, 'SMS body must not be null.');
        System.assert(result.contains('654321'),            'Verification code must appear in body.');
        System.assert(result.containsIgnoreCase('approve'), 'Approve URL must appear in body.');
        System.assert(result.containsIgnoreCase('reject'),  'Reject URL must appear in body.');
    }

    @IsTest
    static void testBuildSmsBody_NullTemplate_ThrowsException() {

        Account memberAcct = [
            SELECT Id, Name
            FROM   Account
            WHERE  IsPersonAccount = true
            LIMIT  1
        ];

        Account_Head_Relationship__c rel = new Account_Head_Relationship__c(
            Approval_Token__c    = 'abc123',
            Verification_Code__c = '654321',
            Token_Expiry__c      = System.now().addDays(7),
            Member_Account__r    = memberAcct
        );

        Boolean exceptionThrown = false;
        try {
            AccountHeadRelationshipSmsQueueable.buildSmsBody(rel, null);
        } catch (Exception ex) {
            exceptionThrown = true;
        }

        System.assertEquals(
            true,
            exceptionThrown,
            'Calling buildSmsBody with a null template must throw a NullPointerException.'
        );
    }

    @IsTest
    static void testQueueable_SmsReceiverNumber_MatchesAuthorizedAccountMobile() {

        List<Account> accounts       = getTwoPersonAccounts();
        Account       authorizedAcct = accounts[0]; // this account's phone should be the receiver
        Account       memberAcct     = accounts[1];

        Account_Head_Relationship__c rel = createRelationship(
            authorizedAcct.Id,
            memberAcct.Id,
            PORTAL_STATUS,
            APPROVAL_TOKEN,
            VERIFICATION_CODE
        );
        insert rel;

        Test.startTest();
        AccountHeadRelationshipSmsQueueable.sendSms(new Set<Id>{ rel.Id });
        Test.stopTest();

        List<sra__Message_History__c> smsList = fetchSmsForRelationship(rel.Id);

        System.assert(!smsList.isEmpty(), 'SMS record must exist.');

        System.assertEquals(
            authorizedAcct.PersonMobilePhone,
            smsList[0].sra__Receiver_Number__c,
            'Receiver number must match the authorized (child) account mobile phone.'
        );
    }
}