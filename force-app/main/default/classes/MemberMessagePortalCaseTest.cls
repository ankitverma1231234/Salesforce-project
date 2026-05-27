@IsTest(SeeAllData=true)
public class MemberMessagePortalCaseTest {

    @IsTest
    static void testGetPersonAccount() {

        // Fetch existing Person Account from org
        Account pa = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonContactId != null
            LIMIT 1
        ];

        Test.startTest();
        Account result = MemberMessagePortalCase.getPersonAccount(pa.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Person Account should be returned');
        System.assertEquals(pa.Id, result.Id, 'Account Id should match');
        System.assertNotEquals(null, result.PersonContactId, 'Person Contact should exist');
    }

    @IsTest
    static void testCreateCase() {

        Account pa = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonContactId != null
            LIMIT 1
        ];

        Test.startTest();
        Id caseId = MemberMessagePortalCase.createCase(
            'Test Case Subject',
            'Test Case Description',
            pa.Id,
            pa.PersonContactId
        );
        Test.stopTest();

        Case c = [
            SELECT Subject, Status, Case_Type__c, AccountId, ContactId
            FROM Case
            WHERE Id = :caseId
        ];

        System.assertEquals('Test Case Subject', c.Subject);
        System.assertEquals('New', c.Status);
        System.assertEquals('Portal Messages', c.Case_Type__c);
        System.assertEquals(pa.Id, c.AccountId);
        System.assertEquals(pa.PersonContactId, c.ContactId);
    }

    @IsTest
    static void testLinkFilesToCase() {

        // Existing Person Account
        Account pa = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonContactId != null
            LIMIT 1
        ];

        // Create Case
        Case c = new Case(
            Subject = 'File Link Test',
            Status = 'New',
            AccountId = pa.Id,
            ContactId = pa.PersonContactId
        );
        insert c;

        // Create File with Source__c
ContentVersion cv = new ContentVersion(
    Title = 'Test File',
    PathOnClient = 'TestFile.pdf',
    VersionData = Blob.valueOf('Test Content'),
    Source__c = 'Metriport'
);
insert cv;

        // Fetch ContentDocumentId
        Id contentDocId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ].ContentDocumentId;

        Test.startTest();
        MemberMessagePortalCase.linkFilesToCase(
            c.Id,
            new List<Id>{ contentDocId }
        );
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :c.Id
        ];

        System.assertEquals(1, links.size(), 'File should be linked to the Case');
    }
}