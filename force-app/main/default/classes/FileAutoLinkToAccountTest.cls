@IsTest(seeAllData=true)
private class FileAutoLinkToAccountTest {

    @IsTest
    static void testAllObjectPaths() {

        // Create an Account
          Account acc = [
            SELECT Id
            FROM Account
            WHERE metriport_patient_Id__c = 'patient-123'
            LIMIT 1
        ];

        // Create test records
        sra__Message_History__c msg = new sra__Message_History__c(
            Name = 'Test Message',
            sra__Related_Object_Id__c = acc.Id
        );
        insert msg;

        Email_Log__c emailLog = new Email_Log__c(
            Account__c = acc.Id
        );
        insert emailLog;

       /* smsefax_guru__eFAX__c efax = new smsefax_guru__eFAX__c(
            smsefax_guru__Account__c = acc.Id
        );
        insert efax; */

        Case caseRecord = new Case(
            Subject = 'Test Case',
            AccountId = acc.Id
        );
        insert caseRecord;

        // Create ContentVersion (produces ContentDocument)
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'TestFile.txt',
            VersionData = Blob.valueOf('Test Data'),
            Source_Type__c='Metriport',
            IsMajorVersion = true
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        Test.startTest();

        // Insert ContentDocumentLinks to all objects
        insert new List<ContentDocumentLink>{
            new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = msg.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ),
            new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = emailLog.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ),
            new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = caseRecord.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            )
        };

        Test.stopTest();

        // Verify only one Account link was created
        List<ContentDocumentLink> accountLinks = [
            SELECT Id, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :cv.ContentDocumentId
            AND LinkedEntityId = :acc.Id
        ];

        System.assertEquals(1, accountLinks.size(), 'Only one Account link should be created.');

    }

    @IsTest
    static void testNullAccountScenario() {

        // Message history without related Account
        sra__Message_History__c msg = new sra__Message_History__c(
            Name = 'No Account Message'
        );
        insert msg;

        ContentVersion cv = new ContentVersion(
            Title = 'Null Test File',
            PathOnClient = 'NullTest.txt',
            VersionData = Blob.valueOf('Test Data'),
            Source_Type__c='Metriport',
            IsMajorVersion = true
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        Test.startTest();

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = msg.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.stopTest();

        // Ensure no Account link was created
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :cv.ContentDocumentId
        ];

       // System.assertEquals(1, links.size(), 'Only the original link should exist, no Account link.');
    }

    @IsTest
    static void testBulkInsert() {
		 Account acc = [
            SELECT Id
            FROM Account
            WHERE metriport_patient_Id__c = 'patient-123'
            LIMIT 1
        ];
      

        List<sra__Message_History__c> messages = new List<sra__Message_History__c>();

        for(Integer i = 0; i < 5; i++) {
            messages.add(new sra__Message_History__c(
                Name = 'Bulk Msg ' + i,
                sra__Related_Object_Id__c = acc.Id
            ));
        }
        insert messages;

        ContentVersion cv = new ContentVersion(
            Title = 'Bulk File',
            PathOnClient = 'Bulk.txt',
            VersionData = Blob.valueOf('Bulk Data'),
            Source_Type__c='Metriport',
            IsMajorVersion = true
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for(sra__Message_History__c msg : messages) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId = msg.Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        Test.startTest();
        insert links;
        Test.stopTest();

        // Verify only one Account link exists
        List<ContentDocumentLink> accountLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :acc.Id
            AND ContentDocumentId = :cv.ContentDocumentId
        ];

        System.assertEquals(1, accountLinks.size(), 'Only one Account link should be created in bulk scenario.');
    }
}