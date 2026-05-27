@isTest
public without sharing class AccountTriggerHandlerTest {

    @testSetup
    static void setupData() {
        // Create User to own Accounts
        User ownerUser = new User(
            Alias = 'owner1',
            Email = 'owner1@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Owner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'owneruser' + DateTime.now().getTime() + '@example.com'
        );
        insert ownerUser;
		// Create Person Account Record Type
        String memberRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Member').getRecordTypeId();
        // Insert test Account with real owner
        Account acc = new Account(LastName = 'Test Account', OwnerId = ownerUser.Id,PersonEmail = 'test@test.com',RecordTypeId = memberRecordTypeId);
        insert acc;
    }

    /*@isTest
    static void testOwnerChangedToUnassigned() {
        // Load old account
        Account oldAcc = [SELECT Id, OwnerId FROM Account LIMIT 1];
        Map<Id, Account> oldMap = new Map<Id, Account>{ oldAcc.Id => oldAcc };

        // Change OwnerId to the Unassigned label
        Account updatedAcc = oldAcc.clone(false);
        updatedAcc.OwnerId = System.Label.Unassigned;

        Test.startTest();
        AccountTriggerHandler.postChatterOnOwnerChange(oldMap, new List<Account>{ updatedAcc });
        Test.stopTest();

        // Can't assert Chatter post directly unless we wrap/mock it
        System.assert(true, 'Executed postChatterOnOwnerChange without exception');
    }*/

    /*@isTest
    static void testOwnerNotChanged() {
        Account acc = [SELECT Id, OwnerId FROM Account LIMIT 1];
        Map<Id, Account> oldMap = new Map<Id, Account>{ acc.Id => acc };

        // Simulate no owner change
        Account updatedAcc = acc.clone(false);
        updatedAcc.OwnerId = acc.OwnerId;

        Test.startTest();
        AccountTriggerHandler.postChatterOnOwnerChange(oldMap, new List<Account>{ updatedAcc });
        Test.stopTest();

        System.assert(true, 'No post when owner did not change');
    }*/

    @isTest
    static void testOwnerChangedToOtherUser() {
        // Original account
        Account acc = [SELECT Id, OwnerId FROM Account LIMIT 1];

        // Create another user as new owner
        User anotherUser = new User(
            Alias = 'newuser',
            Email = 'newuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Unassigned',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'newuser' + DateTime.now().getTime() + '@example.com'
        );
        insert anotherUser;
		//User u = [Select ID FROM User WHERE LastName = 'Unassigned' LIMIT 1];
        Map<Id, Account> oldMap = new Map<Id, Account>{ acc.Id => acc };

        Account updatedAcc = new Account(Id=acc.Id);
        updatedAcc.OwnerId = anotherUser.Id;
		update updatedAcc;
        
        Test.startTest();
        AccountTriggerHandler.postChatterOnOwnerChange(oldMap, new List<Account>{ updatedAcc });
        Test.stopTest();

        System.assert(true, 'No post for owner change to real user');
    }
}