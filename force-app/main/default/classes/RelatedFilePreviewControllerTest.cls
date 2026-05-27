@isTest
private class RelatedFilePreviewControllerTest {

    @testSetup
    static void setupTestData() {
        // Create primary file
        ContentVersion primaryVersion = new ContentVersion(
            Title = 'Primary Document',
            PathOnClient = 'Primary_Document.txt',
            VersionData = Blob.valueOf('Primary file content'),
            IsMajorVersion = true
        );
        insert primaryVersion;

        // Get the generated ContentDocumentId for the primary file
        Id primaryCdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :primaryVersion.Id].ContentDocumentId;

        // Create related file and link it to the primary ContentDocumentId
        ContentVersion relatedVersion = new ContentVersion(
            Title = 'Related Document',
            PathOnClient = 'Related_Document.png',
            VersionData = Blob.valueOf('Fake Image Data'),
            IsMajorVersion = true,
            Related_File__c = primaryCdId // Set custom relation field
        );
        insert relatedVersion;
    }

    @isTest
    static void testGetRelatedFile_Success() {
        // Query the primary file's Document ID
        ContentVersion primaryCv = [SELECT ContentDocumentId FROM ContentVersion WHERE Title = 'Primary Document' LIMIT 1];
        
        Test.startTest();
        // Invoke controller
        RelatedFilePreviewController.FileWrapper result = RelatedFilePreviewController.getRelatedFile(primaryCv.ContentDocumentId);
        Test.stopTest();

        System.assertNotEquals(null, result, 'The related file wrapper should not be null');
        System.assertEquals('Related Document', result.title, 'The title should match the related document');
        System.assertEquals('png', result.fileType, 'The file type should be transformed to lowercase');
    }

    @isTest
    static void testGetRelatedFile_NoResults() {
        // Query the related file's Document ID (which doesn't have a file related to IT)
        ContentVersion relatedCv = [SELECT ContentDocumentId FROM ContentVersion WHERE Title = 'Related Document' LIMIT 1];
        
        Test.startTest();
        // Invoke controller with an ID that has no children
        RelatedFilePreviewController.FileWrapper result = RelatedFilePreviewController.getRelatedFile(relatedCv.ContentDocumentId);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when no related file is found');
    }

    @isTest
    static void testGetRelatedFile_NullParam() {
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            RelatedFilePreviewController.getRelatedFile(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // Native AuraHandledException messages are obfuscated to 'Script-thrown exception' in test context
            System.assertEquals('Script-thrown exception', e.getMessage(), 'Should capture obfuscated error message');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'An AuraHandledException should have been thrown for null parameter');
    }
}