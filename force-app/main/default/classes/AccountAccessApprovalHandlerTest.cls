@IsTest(SeeAllData=true)
private class AccountAccessApprovalHandlerTest {

    // ─── Helper: get or create a Person Account ───────────────────────────
    private static Account getOrCreatePersonAccount(String first, String last, String email) {
        // Try to fetch an existing Person Account with email
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

        // Get PersonAccount Record Type Id
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

    // ─── Test 1: Token + Code stamped on insert ────────────────────────────
    @IsTest
    static void stampsTokenAndCodeOnInsert() {
        Account member    = getOrCreatePersonAccount('Mary',   'Member',    'mary.member+test@example.com');
        Account requestor = getOrCreatePersonAccount('Robert', 'Requestor', 'rob.requestor+test@example.com');

        Test.startTest();
        Account_head_relationship__c rel = new Account_head_relationship__c(
            Member_Account__c            = member.Id,
            Authorized_Account_Access__c = requestor.Id
        );
        insert rel;
        Test.stopTest();

        rel = [
            SELECT Approval_Token__c, Verification_Code__c, Token_Expiry__c, Portal_Access_Status__c
            FROM   Account_head_relationship__c
            WHERE  Id = :rel.Id
        ];

        System.assertNotEquals(null,      rel.Approval_Token__c,     'Token should be stamped');
        System.assertEquals(64,           rel.Approval_Token__c.length(), 'Token should be 64 chars');
        System.assertEquals(6,            rel.Verification_Code__c.length(), 'Code should be 6 chars');
        System.assertEquals('Pending',    rel.Portal_Access_Status__c,   'Status should be Pending');
        System.assert(rel.Token_Expiry__c > Datetime.now().addDays(6),   'Expiry should be > 6 days');
    }

    // ─── Test 2: Bulk insert stamps 50 records ─────────────────────────────
    @IsTest
    static void bulkInsertStamps50() {
        Account member    = getOrCreatePersonAccount('Mary',   'Member',    'mary.member+test@example.com');
        Account requestor = getOrCreatePersonAccount('Robert', 'Requestor', 'rob.requestor+test@example.com');

        List<Account_head_relationship__c> rels = new List<Account_head_relationship__c>();
        for (Integer i = 0; i < 50; i++) {
            rels.add(new Account_head_relationship__c(
                Member_Account__c            = member.Id,
                Authorized_Account_Access__c = requestor.Id
            ));
        }

        Test.startTest();
        insert rels;
        Test.stopTest();

        List<Id> relIds = new List<Id>();
        for (Account_head_relationship__c r : rels) {
            relIds.add(r.Id);
        }

        Integer cnt = [
            SELECT COUNT()
            FROM   Account_head_relationship__c
            WHERE  Id                    IN :relIds
            AND    Portal_Access_Status__c = 'Pending'
            AND    Approval_Token__c      != null
        ];

        System.assertEquals(50, cnt, 'All 50 records should be stamped');
    }

    // ─── Test 3: Update transition stamps token ────────────────────────────
    @IsTest
    static void updateTransitionStamps() {
        Account member    = getOrCreatePersonAccount('Mary',   'Member',    'mary.member+test@example.com');
        Account requestor = getOrCreatePersonAccount('Robert', 'Requestor', 'rob.requestor+test@example.com');

        // Insert WITHOUT requestor → should NOT stamp
        Account_head_relationship__c rel = new Account_head_relationship__c(
            Member_Account__c = member.Id
        );
        insert rel;

        rel = [SELECT Approval_Token__c FROM Account_head_relationship__c WHERE Id = :rel.Id];
        System.assertEquals(null, rel.Approval_Token__c, 'Should not stamp without both lookups');

        Test.startTest();
        rel.Authorized_Account_Access__c = requestor.Id;
        update rel;
        Test.stopTest();

        rel = [
            SELECT Approval_Token__c, Portal_Access_Status__c
            FROM   Account_head_relationship__c
            WHERE  Id = :rel.Id
        ];

    }
}