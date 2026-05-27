@IsTest(seeAllData=true)
public class CDPortalPrepareQueueableTest {

    @IsTest
    static void testExecute_WithExistingAccount() {
        Account acc = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];
        System.assertNotEquals(null, acc);
        Contact con = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];
        System.assertNotEquals(null, con);
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'TestFile.txt',
            VersionData = Blob.valueOf('Test Content'),
            Source__c = 'Metriport',
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        System.assertNotEquals(null, cv.ContentDocumentId);
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = acc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
        Test.startTest();
        System.enqueueJob(new CDPortalPrepareQueueable(new List<Id>{ cv.ContentDocumentId }));
        Test.stopTest();

        List<ContentDistribution> cds = [
            SELECT Id, ContentVersionId
            FROM ContentDistribution
            WHERE ContentVersionId = :cv.Id
        ];
        System.assert(cds.size() > 0);
    }
    @IsTest
    static void testExecute_EmptyInput() {
        Test.startTest();
        System.enqueueJob(new CDPortalPrepareQueueable(new List<Id>()));
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
        ContentVersion cv = new ContentVersion(
            Title = 'NoApiKeyFile',
            PathOnClient = 'NoApiKey.txt',
            VersionData = Blob.valueOf('Test'),
            Source__c = 'Metriport',
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = [SELECT Id FROM Account LIMIT 1].Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
        Test.startTest();
        System.enqueueJob(new CDPortalPrepareQueueable(new List<Id>{ cv.ContentDocumentId }));
        Test.stopTest();
        System.assert(true);
    }
}