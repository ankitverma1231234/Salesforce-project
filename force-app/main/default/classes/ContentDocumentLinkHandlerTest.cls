@isTest
public class ContentDocumentLinkHandlerTest {
    @testSetup
    static void setupTestData() {
        Id memberRecordTypeId =  Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId();
        Account testAccount = new Account(FirstName = 'Test Account',LastName = 'Member',PersonEmail='test123@test.com',RecordTypeId = memberRecordTypeId);
        insert testAccount;

        ContentVersion testVersion = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDoc.pdf',
            VersionData = Blob.valueOf('Test Data'),
            FirstPublishLocationId = testAccount.Id
        );
        insert testVersion;

        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId 
            FROM ContentVersion 
            WHERE Id = :testVersion.Id 
            LIMIT 1
        ];

        Id contentDocumentId = insertedVersion.ContentDocumentId;

        List<ContentDocumentLink> existingLinks = [
            SELECT Id FROM ContentDocumentLink 
            WHERE ContentDocumentId = :contentDocumentId 
            AND LinkedEntityId = :testAccount.Id
        ];

        if (existingLinks.isEmpty()) {
            ContentDocumentLink testLink = new ContentDocumentLink(
                ContentDocumentId = contentDocumentId,
                LinkedEntityId = testAccount.Id,
                ShareType = 'I'
            );
            insert testLink;
        }
    }

    @isTest
    static void testContentDocumentLinkTrigger() {
        ContentVersion insertedVersion = [
            SELECT Id, ContentDocumentId FROM ContentVersion LIMIT 1
        ];

        ContentDocumentLink insertedLink = [
            SELECT Id, Visibility, ShareType 
            FROM ContentDocumentLink 
            WHERE ContentDocumentId = :insertedVersion.ContentDocumentId
            LIMIT 1
        ];

        System.assertEquals('AllUsers', insertedLink.Visibility, 'Visibility should be set to AllUsers');
        //System.assertEquals('V', insertedLink.ShareType, 'ShareType should be set to V');
    }
}