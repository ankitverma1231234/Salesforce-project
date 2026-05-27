@isTest
private class FileAttachmentQueueableTest {
    
    @testSetup
    static void setupTestData() {
        // Create a test Case
        Case testCase = new Case(
            Subject = 'Test Case for File Attachments',
            Status = 'New',
            Origin = 'Web'
        );
        insert testCase;
    }
    
    @isTest
    static void testSuccessfulFileDownloadAndInsert() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        // Set up mock callout
        Test.setMock(HttpCalloutMock.class, new FileDownloadMockSuccess());
        
        // Create file wrappers
        List<CaseMedicalChatterCrate.FileAttachmentWrapper> fileWrappers = 
            new List<CaseMedicalChatterCrate.FileAttachmentWrapper>();
        
        CaseMedicalChatterCrate.FileAttachmentWrapper wrapper1 = 
            new CaseMedicalChatterCrate.FileAttachmentWrapper();
        wrapper1.fileUrl = 'https://example.com/file1.pdf';
        wrapper1.filename = 'TestFile1.pdf';
        wrapper1.caseId = testCase.Id;
        
        CaseMedicalChatterCrate.FileAttachmentWrapper wrapper2 = 
            new CaseMedicalChatterCrate.FileAttachmentWrapper();
        wrapper2.fileUrl = 'https://example.com/file2.pdf';
        wrapper2.filename = 'TestFile2.pdf';
        wrapper2.caseId = testCase.Id;
        
        fileWrappers.add(wrapper1);
        fileWrappers.add(wrapper2);
        
        Test.startTest();
        System.enqueueJob(new FileAttachmentQueueable(fileWrappers));
        Test.stopTest();
        
        // Verify ContentVersions were created
        List<ContentVersion> insertedFiles = [
            SELECT Id, Title, PathOnClient, FirstPublishLocationId 
            FROM ContentVersion 
            WHERE FirstPublishLocationId = :testCase.Id
        ];
        
        System.assertEquals(2, insertedFiles.size(), 'Expected 2 files to be inserted');
        System.assertEquals('TestFile1.pdf', insertedFiles[0].Title, 'File title should match');
    }
    
    @isTest
    static void testFailedHttpCallout() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        // Set up mock callout that returns error
        Test.setMock(HttpCalloutMock.class, new FileDownloadMockFailure());
        
        List<CaseMedicalChatterCrate.FileAttachmentWrapper> fileWrappers = 
            new List<CaseMedicalChatterCrate.FileAttachmentWrapper>();
        
        CaseMedicalChatterCrate.FileAttachmentWrapper wrapper = 
            new CaseMedicalChatterCrate.FileAttachmentWrapper();
        wrapper.fileUrl = 'https://example.com/file.pdf';
        wrapper.filename = 'TestFile.pdf';
        wrapper.caseId = testCase.Id;
        
        fileWrappers.add(wrapper);
        
        Test.startTest();
        System.enqueueJob(new FileAttachmentQueueable(fileWrappers));
        Test.stopTest();
        
    }

    @isTest
    static void testBlankFileUrlOrFilename() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new FileDownloadMockSuccess());
        
        List<CaseMedicalChatterCrate.FileAttachmentWrapper> fileWrappers = 
            new List<CaseMedicalChatterCrate.FileAttachmentWrapper>();
        
        // Wrapper with blank URL
        CaseMedicalChatterCrate.FileAttachmentWrapper wrapper1 = 
            new CaseMedicalChatterCrate.FileAttachmentWrapper();
        wrapper1.fileUrl = '';
        wrapper1.filename = 'TestFile1.pdf';
        wrapper1.caseId = testCase.Id;
        
        // Wrapper with blank filename
        CaseMedicalChatterCrate.FileAttachmentWrapper wrapper2 = 
            new CaseMedicalChatterCrate.FileAttachmentWrapper();
        wrapper2.fileUrl = 'https://example.com/file2.pdf';
        wrapper2.filename = '';
        wrapper2.caseId = testCase.Id;
        
        // Valid wrapper
        CaseMedicalChatterCrate.FileAttachmentWrapper wrapper3 = 
            new CaseMedicalChatterCrate.FileAttachmentWrapper();
        wrapper3.fileUrl = 'https://example.com/file3.pdf';
        wrapper3.filename = 'TestFile3.pdf';
        wrapper3.caseId = testCase.Id;
        
        fileWrappers.add(wrapper1);
        fileWrappers.add(wrapper2);
        fileWrappers.add(wrapper3);
        
        Test.startTest();
        System.enqueueJob(new FileAttachmentQueueable(fileWrappers));
        Test.stopTest();
        
        // Only the valid wrapper should create a file
        List<ContentVersion> insertedFiles = [
            SELECT Id 
            FROM ContentVersion 
            WHERE FirstPublishLocationId = :testCase.Id
        ];
        
        System.assertEquals(1, insertedFiles.size(), 'Only 1 valid file should be inserted');
    }
    
    @isTest
    static void testBatchProcessing100Files() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new FileDownloadMockSuccess());
        
        List<CaseMedicalChatterCrate.FileAttachmentWrapper> fileWrappers = 
            new List<CaseMedicalChatterCrate.FileAttachmentWrapper>();
        
        // Create 100 file wrappers
        for (Integer i = 0; i < 100; i++) {
            CaseMedicalChatterCrate.FileAttachmentWrapper wrapper = 
                new CaseMedicalChatterCrate.FileAttachmentWrapper();
            wrapper.fileUrl = 'https://example.com/file' + i + '.pdf';
            wrapper.filename = 'TestFile' + i + '.pdf';
            wrapper.caseId = testCase.Id;
            fileWrappers.add(wrapper);
        }
        
        Test.startTest();
        System.enqueueJob(new FileAttachmentQueueable(fileWrappers));
        Test.stopTest();
        
        // Verify all 100 files were processed
        List<ContentVersion> insertedFiles = [
            SELECT Id 
            FROM ContentVersion 
            WHERE FirstPublishLocationId = :testCase.Id
        ];
        
        System.assertEquals(100, insertedFiles.size(), 'All 100 files should be processed');
    }
    
    @isTest
    static void testExceptionDuringFileDownload() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        //Test.setMock(HttpCalloutMock.class, new FileDownloadMockException());
        
        List<CaseMedicalChatterCrate.FileAttachmentWrapper> fileWrappers = 
            new List<CaseMedicalChatterCrate.FileAttachmentWrapper>();
        
        CaseMedicalChatterCrate.FileAttachmentWrapper wrapper = 
            new CaseMedicalChatterCrate.FileAttachmentWrapper();
        wrapper.fileUrl = 'https://example.com/file.pdf';
        wrapper.filename = 'TestFile.pdf';
        wrapper.caseId = testCase.Id;
        
        fileWrappers.add(wrapper);
        
        Test.startTest();
        System.enqueueJob(new FileAttachmentQueueable(fileWrappers));
        Test.stopTest();
        
        // Should handle exception gracefully
        List<ContentVersion> insertedFiles = [SELECT Id FROM ContentVersion];
        System.assertEquals(0, insertedFiles.size(), 'No files should be inserted on exception');
    }
    
    // Mock class for successful HTTP response
    private class FileDownloadMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody('Test file content');
            res.setHeader('Content-Type', 'application/pdf');
            return res;
        }
    }
    
    // Mock class for failed HTTP response
    private class FileDownloadMockFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setStatus('Not Found');
            return res;
        }
    }
}