@isTest(SeeAllData=true)
public class DeleteAccountHeadTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static String uid() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static Id getPersonAccountRecordTypeId() {
        return [
            SELECT Id FROM RecordType
            WHERE  SObjectType = 'Account'
            AND    IsPersonType = true
            LIMIT  1
        ].Id;
    }

    private static Account createPersonAccount(
        String firstName, String lastName,
        String email,     String phone
    ) {
        Account a = new Account(
            RecordTypeId      = getPersonAccountRecordTypeId(),
            FirstName         = firstName,
            LastName          = lastName,
            PersonEmail       = email,
            PersonMobilePhone = phone
        );

        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave        = true;
        dml.duplicateRuleHeader.runAsCurrentUser = true;

        Database.SaveResult sr = Database.insert(a, dml);
        if (!sr.isSuccess()) {
            throw new DmlException(
                'createPersonAccount failed: ' + sr.getErrors()[0].getMessage()
            );
        }
        return a;
    }

    private static Account_Head_Relationship__c createJunction(Id parentId, Id childId) {
        Account_Head_Relationship__c j = new Account_Head_Relationship__c(
            Member_Account__c            = parentId,
            Authorized_Account_Access__c = childId
        );
        insert j;
        return j;
    }

    private static List<Account_Head_Relationship__c> createMultipleJunctions(
        Id parentId, List<Id> childIds
    ) {
        List<Account_Head_Relationship__c> junctions = new List<Account_Head_Relationship__c>();
        for (Id childId : childIds) {
            junctions.add(new Account_Head_Relationship__c(
                Member_Account__c            = parentId,
                Authorized_Account_Access__c = childId
            ));
        }
        insert junctions;
        return junctions;
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 1 — Single record deletion
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testSingleId_DeletesRecord() {
        String  u      = uid();
        Account parent = createPersonAccount('DelHead' + u, 'S1' + u,
            'del.head.s1.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('DelChild' + u, 'S1' + u,
            'del.child.s1.' + u + '@test.com', (u + '1').left(10));

        Account_Head_Relationship__c jr = createJunction(parent.Id, child.Id);

        Test.startTest();
        System.enqueueJob(
            new DeleteAccountHeadRelationshipQueueable(new List<String>{ jr.Id })
        );
        Test.stopTest();

        List<Account_Head_Relationship__c> remaining = [
            SELECT Id FROM Account_Head_Relationship__c WHERE Id = :jr.Id
        ];
        System.assertEquals(0, remaining.size(),
            'Junction record should have been deleted.');
    }

    @isTest
    static void testSingleId_ParentAndChildAccountsUntouched() {
        String  u      = uid();
        Account parent = createPersonAccount('DelHead' + u, 'S2' + u,
            'del.head.s2.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('DelChild' + u, 'S2' + u,
            'del.child.s2.' + u + '@test.com', (u + '2').left(10));

        Account_Head_Relationship__c jr = createJunction(parent.Id, child.Id);

        Test.startTest();
        System.enqueueJob(
            new DeleteAccountHeadRelationshipQueueable(new List<String>{ jr.Id })
        );
        Test.stopTest();

        // Parent and child Accounts must still exist
        System.assertEquals(1, [SELECT Id FROM Account WHERE Id = :parent.Id].size(),
            'Parent account should still exist.');
        System.assertEquals(1, [SELECT Id FROM Account WHERE Id = :child.Id].size(),
            'Child account should still exist.');
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 2 — Multiple records deletion
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testMultipleIds_AllDeleted() {
        String  u      = uid();
        Account parent = createPersonAccount('DelHead' + u, 'M1' + u,
            'del.head.m1.' + u + '@test.com', u.left(10));

        Account c1 = createPersonAccount('MC1' + u, 'M1' + u,
            'mc1.' + u + '@test.com', (u + '3').left(10));
        Account c2 = createPersonAccount('MC2' + u, 'M1' + u,
            'mc2.' + u + '@test.com', (u + '4').left(10));
        Account c3 = createPersonAccount('MC3' + u, 'M1' + u,
            'mc3.' + u + '@test.com', (u + '5').left(10));

        List<Account_Head_Relationship__c> junctions =
            createMultipleJunctions(parent.Id, new List<Id>{ c1.Id, c2.Id, c3.Id });

        List<String> ids = new List<String>();
        for (Account_Head_Relationship__c j : junctions) {
            ids.add(j.Id);
        }

        Test.startTest();
        System.enqueueJob(new DeleteAccountHeadRelationshipQueueable(ids));
        Test.stopTest();

        List<Account_Head_Relationship__c> remaining = [
            SELECT Id FROM Account_Head_Relationship__c
            WHERE  Id IN :ids
        ];
        System.assertEquals(0, remaining.size(),
            'All junction records should have been deleted.');
    }

    @isTest
    static void testMultipleIds_OnlyTargetedRecordsDeleted() {
        String  u      = uid();
        Account parent = createPersonAccount('DelHead' + u, 'M2' + u,
            'del.head.m2.' + u + '@test.com', u.left(10));

        Account c1 = createPersonAccount('MC1' + u, 'M2' + u,
            'mc1.m2.' + u + '@test.com', (u + '6').left(10));
        Account c2 = createPersonAccount('MC2' + u, 'M2' + u,
            'mc2.m2.' + u + '@test.com', (u + '7').left(10));

        // jr1 = to be deleted, jr2 = must survive
        Account_Head_Relationship__c jr1 = createJunction(parent.Id, c1.Id);
        Account_Head_Relationship__c jr2 = createJunction(parent.Id, c2.Id);

        Test.startTest();
        System.enqueueJob(
            new DeleteAccountHeadRelationshipQueueable(new List<String>{ jr1.Id })
        );
        Test.stopTest();

        System.assertEquals(0,
            [SELECT Id FROM Account_Head_Relationship__c WHERE Id = :jr1.Id].size(),
            'jr1 should be deleted.');
        System.assertEquals(1,
            [SELECT Id FROM Account_Head_Relationship__c WHERE Id = :jr2.Id].size(),
            'jr2 should NOT be deleted.');
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 3 — Edge cases
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testEmptyList_NoException() {
        Test.startTest();
        // Should complete silently without any exception
        System.enqueueJob(
            new DeleteAccountHeadRelationshipQueueable(new List<String>())
        );
        Test.stopTest();

        // If we reach here the queueable handled the empty list gracefully
        System.assert(true, 'Empty list should not throw an exception.');
    }

    @isTest
    static void testNullList_NoException() {
        Test.startTest();
        System.enqueueJob(
            new DeleteAccountHeadRelationshipQueueable(null)
        );
        Test.stopTest();

        System.assert(true, 'Null list should not throw an exception.');
    }

    @isTest
    static void testNonExistentId_NoException_NothingDeleted() {
        String fakeId = 'a4B000000000001AAA';

        // Capture total junction count before the job
        Integer countBefore = [
            SELECT COUNT() FROM Account_Head_Relationship__c
        ];

        Test.startTest();
        System.enqueueJob(
            new DeleteAccountHeadRelationshipQueueable(new List<String>{ fakeId })
        );
        Test.stopTest();

        Integer countAfter = [
            SELECT COUNT() FROM Account_Head_Relationship__c
        ];
        System.assertEquals(countBefore, countAfter,
            'No records should be deleted when ID does not exist.');
    }

    @isTest
    static void testMixedValidAndInvalidIds_ValidOneDeleted() {
        String  u      = uid();
        Account parent = createPersonAccount('DelHead' + u, 'MX' + u,
            'del.head.mx.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('DelChild' + u, 'MX' + u,
            'del.child.mx.' + u + '@test.com', (u + '8').left(10));

        Account_Head_Relationship__c jr = createJunction(parent.Id, child.Id);
        String fakeId = 'a4B000000000002AAA';

        Test.startTest();
        System.enqueueJob(
            new DeleteAccountHeadRelationshipQueueable(
                new List<String>{ fakeId, jr.Id }
            )
        );
        Test.stopTest();

        List<Account_Head_Relationship__c> remaining = [
            SELECT Id FROM Account_Head_Relationship__c WHERE Id = :jr.Id
        ];
        System.assertEquals(0, remaining.size(),
            'The valid junction record should have been deleted.');
    }

    @isTest
    static void testDuplicateIds_DeletedOnceNoError() {
        String  u      = uid();
        Account parent = createPersonAccount('DelHead' + u, 'DUP' + u,
            'del.head.dup.' + u + '@test.com', u.left(10));
        Account child  = createPersonAccount('DelChild' + u, 'DUP' + u,
            'del.child.dup.' + u + '@test.com', (u + '9').left(10));

        Account_Head_Relationship__c jr = createJunction(parent.Id, child.Id);

        // Same ID supplied twice — should not throw, deleted exactly once
        Test.startTest();
        System.enqueueJob(
            new DeleteAccountHeadRelationshipQueueable(
                new List<String>{ jr.Id, jr.Id }
            )
        );
        Test.stopTest();

        List<Account_Head_Relationship__c> remaining = [
            SELECT Id FROM Account_Head_Relationship__c WHERE Id = :jr.Id
        ];
        System.assertEquals(0, remaining.size(),
            'Duplicate IDs should still result in a clean delete with no error.');
    }


    // ══════════════════════════════════════════════════════════════════════════
    // SECTION 4 — Batch chunking  (> 200 records in one call)
    // ══════════════════════════════════════════════════════════════════════════

    @isTest
    static void testBatchChunking_201Records_FirstBatchDeleted() {
        String  u      = uid();
        Account parent = createPersonAccount('BHead' + u, 'Batch' + u,
            'b.head.' + u + '@test.com', u.left(10));

        // Create 201 child accounts and junctions
        List<Account> children = new List<Account>();
        Id rtId = getPersonAccountRecordTypeId();
        for (Integer i = 0; i < 201; i++) {
            children.add(new Account(
                RecordTypeId      = rtId,
                FirstName         = 'BatchChild' + i + u,
                LastName          = 'Batch' + u,
                PersonEmail       = 'bc' + i + '.' + u + '@test.com',
                PersonMobilePhone = String.valueOf(i).leftPad(10, '0')
            ));
        }

        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave        = true;
        dml.duplicateRuleHeader.runAsCurrentUser = true;
        Database.insert(children, dml);

        List<Account_Head_Relationship__c> junctions =
            new List<Account_Head_Relationship__c>();
        for (Account c : children) {
            junctions.add(new Account_Head_Relationship__c(
                Member_Account__c            = parent.Id,
                Authorized_Account_Access__c = c.Id
            ));
        }
        insert junctions;

        List<String> ids = new List<String>();
        for (Account_Head_Relationship__c j : junctions) {
            ids.add(j.Id);
        }

        Test.startTest();
        System.enqueueJob(new DeleteAccountHeadRelationshipQueueable(ids));
        Test.stopTest();   // only one enqueueJob fires inside Test context

        // First 200 should be deleted; 201st survives until the chained job runs
        // (chained jobs don't execute in Test context — verify first batch only)
        List<Account_Head_Relationship__c> remaining = [
            SELECT Id FROM Account_Head_Relationship__c
            WHERE  Member_Account__c = :parent.Id
        ];
        System.assertEquals(1, remaining.size(),
            'First 200 records should be deleted; 1 remains for the chained queueable.');
    }
}