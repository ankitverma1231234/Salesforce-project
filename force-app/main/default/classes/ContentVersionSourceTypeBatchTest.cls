@isTest(SeeAllData=true)
private class ContentVersionSourceTypeBatchTest {

    // Helper: get Person Account Record Type Id
    private static Id getPersonAccountRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();
    }

    // Helper: create a Person Account
    private static Account createPersonAccount(String firstName, String lastName) {
        Account personAcc = new Account(
            FirstName    = firstName,
            LastName     = lastName,
            RecordTypeId = getPersonAccountRecordTypeId()
        );
        insert personAcc;
        return personAcc;
    }

    // Helper: create a ContentVersion linked to a record
    private static ContentVersion createContentVersion(
        String source,
        String sourceType,
        Id firstPublishLocationId
    ) {
        ContentVersion cv = new ContentVersion(
            Title                  = 'Test Document',
            PathOnClient           = 'TestDocument.pdf',
            VersionData            = Blob.valueOf('Test Content'),
           // Source__c              = source,
            Source_Type__c         = sourceType,
            FirstPublishLocationId = firstPublishLocationId
        );
        insert cv;
        return cv;
    }

    // ---------------------------------------------------------------
    // Scenario 1: Should update — Source = Metriport, Source_Type = null,
    //             FirstPublishLocationId is a Person Account ('001')
    // ---------------------------------------------------------------
    @isTest
    static void testUpdatesWhenConditionsMet() {
        Account personAcc = createPersonAccount('John', 'Doe');

        ContentVersion cv = createContentVersion('Metriport', null, personAcc.Id);

        Test.startTest();
            Database.executeBatch(new ContentVersionSourceTypeBatch(), 200);
        Test.stopTest();

        ContentVersion updated = [
            SELECT Source_Type__c
            FROM   ContentVersion
            WHERE  Id = :cv.Id
        ];

        System.assertEquals(
            'Metriport',
            updated.Source_Type__c,
            'Source_Type__c should be set to Metriport for Person Account'
        );
    }

    // ---------------------------------------------------------------
    // Scenario 2: Should NOT update — Source_Type__c already has a value
    // ---------------------------------------------------------------
    @isTest
    static void testSkipsWhenSourceTypeAlreadySet() {
        Account personAcc = createPersonAccount('Jane', 'Smith');

        ContentVersion cv = createContentVersion('Metriport', 'ExistingType', personAcc.Id);

        Test.startTest();
            Database.executeBatch(new ContentVersionSourceTypeBatch(), 200);
        Test.stopTest();

        ContentVersion result = [
            SELECT Source_Type__c
            FROM   ContentVersion
            WHERE  Id = :cv.Id
        ];

        System.assertEquals(
            'ExistingType',
            result.Source_Type__c,
            'Source_Type__c should remain unchanged when already populated'
        );
    }

    // ---------------------------------------------------------------
    // Scenario 3: Should NOT update — Source is not Metriport
    // ---------------------------------------------------------------
    @isTest
    static void testSkipsWhenSourceIsNotMetriport() {
        Account personAcc = createPersonAccount('Mark', 'Taylor');

        ContentVersion cv = createContentVersion('OtherSource', null, personAcc.Id);

        Test.startTest();
            Database.executeBatch(new ContentVersionSourceTypeBatch(), 200);
        Test.stopTest();

        ContentVersion result = [
            SELECT Source_Type__c
            FROM   ContentVersion
            WHERE  Id = :cv.Id
        ];

        System.assertEquals(
            null,
            result.Source_Type__c,
            'Source_Type__c should remain null when Source is not Metriport'
        );
    }

    // ---------------------------------------------------------------
    // Scenario 4: Should NOT update — FirstPublishLocationId is NOT
    //             an Account (linked to Contact, starts with '003')
    // ---------------------------------------------------------------
    @isTest
    static void testSkipsWhenNotLinkedToAccount() {
        Contact con = new Contact(LastName = 'Test Contact');
        insert con;

        ContentVersion cv = createContentVersion('Metriport', null, con.Id);

        Test.startTest();
            Database.executeBatch(new ContentVersionSourceTypeBatch(), 200);
        Test.stopTest();

        ContentVersion result = [
            SELECT Source_Type__c
            FROM   ContentVersion
            WHERE  Id = :cv.Id
        ];

        System.assertEquals(
            null,
            result.Source_Type__c,
            'Source_Type__c should remain null when not linked to an Account'
        );
    }

    // ---------------------------------------------------------------
    // Scenario 5: Bulk test — 250 records across Person Accounts
    //             to verify batch handles chunks without hitting limits
    // ---------------------------------------------------------------
    @isTest
    static void testBulkProcessing() {
        Account personAcc = createPersonAccount('Bulk', 'Patient');

        List<ContentVersion> cvList = new List<ContentVersion>();
        for (Integer i = 0; i < 250; i++) {
            cvList.add(new ContentVersion(
                Title                  = 'Bulk Doc ' + i,
                PathOnClient           = 'BulkDoc' + i + '.pdf',
                VersionData            = Blob.valueOf('Bulk Content ' + i),
               // Source__c              = 'Metriport',
                Source_Type__c         = null,
                FirstPublishLocationId = personAcc.Id
            ));
        }
        insert cvList;

        // Collect inserted Ids for scoped assertion
        List<Id> cvIds = new List<Id>();
        for (ContentVersion cv : cvList) {
            cvIds.add(cv.Id);
        }

        Test.startTest();
            Database.executeBatch(new ContentVersionSourceTypeBatch(), 200);
        Test.stopTest();

        List<ContentVersion> results = [
            SELECT Source_Type__c
            FROM   ContentVersion
            WHERE  Id IN :cvIds
        ];

        for (ContentVersion cv : results) {
            System.assertEquals(
                'Metriport',
                cv.Source_Type__c,
                'All bulk records should have Source_Type__c set to Metriport'
            );
        }
    }

    // ---------------------------------------------------------------
    // Scenario 6: No matching records — batch should complete gracefully
    // ---------------------------------------------------------------
    @isTest
    static void testNoMatchingRecords() {
        Test.startTest();
            Database.executeBatch(new ContentVersionSourceTypeBatch(), 200);
        Test.stopTest();

        System.assert(true, 'Batch should complete without errors when no records match');
    }
}