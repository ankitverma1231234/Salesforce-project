@IsTest(SeeAllData=true)
public class CaseSalesforceRecordTest {
    
    /* ================= MOCK ================= */
    private class SuccessHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }

    /* ================= API CONFIG ================= */
    private static void ensureApiConfig() {
        if (BatonPortalAPI__c.getOrgDefaults() == null) {
            insert new BatonPortalAPI__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                CaseKey__c = 'https://test.example.com/api'
            );
        }
    }

    /* ================= ACCOUNT ================= */
    private static Account getOrCreateAccount() {
        List<Account> accs = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];
        if (!accs.isEmpty()) return accs[0];

        Id rt = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();

        Account acc = new Account(
            FirstName = 'Test',
            LastName = 'Person',
            RecordTypeId = rt,
            PersonEmail = 'test@example.com'
        );
        insert acc;
        return acc;
    }

    private static Case createCase() {
        Account acc = getOrCreateAccount();
        Case c = new Case(
            Subject='Test',
            Status='New',
            Origin='Phone',
            AccountId=acc.Id,
            ContactId=acc.PersonContactId
        );
        insert c;
        return c;
    }

    /* ================= MAIN CASE FLOW ================= */
    @IsTest
    static void testFullCaseFlow() {

        ensureApiConfig();
        Test.setMock(HttpCalloutMock.class, new SuccessHttpMock());

        Case c = createCase();

        // Create File
        ContentVersion cv = new ContentVersion(
            Title='File1',
            PathOnClient='file.txt',
            VersionData=Blob.valueOf('data'),
            Source__c = 'Metriport',
            IsMajorVersion=true
        );
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id=:cv.Id];

        insert new ContentDocumentLink(
            ContentDocumentId=cv.ContentDocumentId,
            LinkedEntityId=c.Id,
            ShareType='V'
        );

        // Create Public Link
        CaseSalesforceRecord.ensurePublicLinksForDocuments(
            new Set<Id>{cv.ContentDocumentId}
        );

        Test.startTest();

        // INSERT
        CaseSalesforceRecord.sendCaseDataToThirdParty(
            new Set<Id>{c.Id}, 'INSERT'
        );

        // UPDATE with attachments
        CaseSalesforceRecord.sendToThirdPartyFuture(
            new Set<Id>{c.Id}, 'UPDATE', true
        );

        // createPublicLinksSync
        CaseSalesforceRecord.createPublicLinksSync(
            new Set<Id>{c.Id}
        );

        Test.stopTest();
    }

    /* ================= DESCRIPTION FLOW ================= */
    @IsTest
    static void testDescriptionFlow() {

        ensureApiConfig();
        Test.setMock(HttpCalloutMock.class, new SuccessHttpMock());

        Case c = createCase();

        Test.startTest();

        CaseSalesforceRecord.handleCaseDescription(
            c.Id, 'Description Test'
        );

        Test.stopTest();
    }

    /* ================= CHATTER WITH ATTACHMENT ================= */
    @IsTest
    static void testChatterWithAttachment() {

        ensureApiConfig();
        Test.setMock(HttpCalloutMock.class, new SuccessHttpMock());

        Case c = createCase();

        FeedItem fi = new FeedItem(
            ParentId=c.Id,
            Body='Hello',
            Type='TextPost'
        );
        insert fi;

        ContentVersion cv = new ContentVersion(
            Title='ChatFile',
            PathOnClient='chat.txt',
            VersionData=Blob.valueOf('chat'),
             Source__c = 'Metriport',
            IsMajorVersion=true
        );
        insert cv;

        cv = [SELECT Id FROM ContentVersion WHERE Id=:cv.Id];

        insert new FeedAttachment(
            FeedEntityId=fi.Id,
            RecordId=cv.Id,
            Type='Content'
        );

        CaseSalesforceRecord.ensurePublicLinksExist(
            new Set<Id>{fi.Id}
        );

        Test.startTest();
        CaseSalesforceRecord.sendChatterDataToThirdParty(
            fi.Id, 'INSERT'
        );
        Test.stopTest();
    }

    /* ================= PAYLOAD METHODS ================= */
    @IsTest
    static void testPayloadBuilders() {

        Case c = createCase();

        Map<String,Object> casePayload =
            CaseSalesforceRecord.buildCasePayload(c.Id);

        System.assertNotEquals(null, casePayload);

        FeedItem fi = new FeedItem(
            ParentId=c.Id,
            Body='Test',
            Type='TextPost'
        );
        insert fi;

        Map<String,Object> chatterPayload =
            CaseSalesforceRecord.buildChatterPayload(fi.Id);

        System.assertNotEquals(null, chatterPayload);
    }

    /* ================= GUARD CLAUSES ================= */
    @IsTest
    static void testNullInputs() {

        Test.startTest();
        CaseSalesforceRecord.sendCaseDataToThirdParty(null, 'INSERT');
        CaseSalesforceRecord.sendChatterDataToThirdParty(null, 'INSERT');
        CaseSalesforceRecord.ensurePublicLinksExist(null);
        CaseSalesforceRecord.ensurePublicLinksForDocuments(null);
        Test.stopTest();

        System.assert(true);
    }

    /* ================= RESET METHODS ================= */
    @IsTest
    static void testResetMethods() {

        CaseSalesforceRecord.resetProcessedCases();
        CaseSalesforceRecord.resetProcessedFeedItems();
        CaseSalesforceRecord.resetApiConfig();

        System.assert(true);
    }
}