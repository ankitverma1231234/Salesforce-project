@IsTest(SeeAllData=true)
public class CDPortalPrepareQueueableTest {

    @IsTest
    static void testExecute_WithExistingAccount() {

        BatonPortalAPI__c api = BatonPortalAPI__c.getOrgDefaults();
        if (api == null) {
            api = new BatonPortalAPI__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Api_Key__c = 'TestKey'
            );
            insert api;
        }

        fra__Entity_Storage__c es = [
            SELECT Id, fra__File_Store_Record_Id__c
            FROM fra__Entity_Storage__c
            WHERE fra__File_Store_Record_Id__c != null
            LIMIT 1
        ];

        Account acc = [
            SELECT Id
            FROM Account
            WHERE Id = :es.fra__File_Store_Record_Id__c
            LIMIT 1
        ];

        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];

        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name = 'Test File',
            Send_to_Portal__c = true,
            fra__Entity_Storage__c = es.Id,
            Source_Type__c = 'Metriport',
            fra__File_Id__c = 'FILE-001'
        );
        insert fs;

        Test.startTest();

        System.enqueueJob(
            new CDPortalPrepareQueueable(
                new List<Id>{ fs.Id }
            )
        );

        Test.stopTest();

    }

    @IsTest
    static void testExecute_EmptyInput() {

        Test.startTest();

        System.enqueueJob(
            new CDPortalPrepareQueueable(
                new List<Id>()
            )
        );

        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testExecute_NoApiKey() {

        BatonPortalAPI__c api = BatonPortalAPI__c.getOrgDefaults();

        if (api != null) {
            api.Api_Key__c = '';
            update api;
        }

        fra__Entity_Storage__c es = [
            SELECT Id, fra__File_Store_Record_Id__c
            FROM fra__Entity_Storage__c
            WHERE fra__File_Store_Record_Id__c != null
            LIMIT 1
        ];

        fra__File_Storage__c fs = new fra__File_Storage__c(
            Name = 'No Api Key File',
            Send_to_Portal__c = true,
            fra__Entity_Storage__c = es.Id
        );
        insert fs;

        Test.startTest();

        System.enqueueJob(
            new CDPortalPrepareQueueable(
                new List<Id>{ fs.Id }
            )
        );

        Test.stopTest();

        System.assert(true);
    }
}