@IsTest(SeeAllData=true)
public class CaseMetriportControllerTest {
    
    // -----------------------------
    // MOCK CALLOUT CLASS
    // -----------------------------
    private class MetriportMock implements HttpCalloutMock {
        
        public HTTPResponse respond(HTTPRequest req) {
            
            HttpResponse res = new HttpResponse();
            
            // First API → Create Document Reference
            if(req.getEndpoint().contains('/medical/v1/document/upload')) {
                
                res.setStatusCode(201);
                res.setBody('{"uploadUrl":"https://mock-upload-url.com"}');
            }
            
            // Second API → Upload PDF
            else if(req.getMethod() == 'PUT') {
                
                res.setStatusCode(200);
                res.setBody('');
            }
            
            return res;
        }
    }
    
    
    // -----------------------------
    // TEST METHOD
    // -----------------------------
    @IsTest
    static void testSendCaseFiles() {
        
        // Get any Account with Metriport Patient Id
        Account acc = [
            SELECT Id, Name, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c != NULL
            LIMIT 1
        ];
        
        // Create Case
        Case c = new Case(
            Subject = 'Test Medical Summary',
            AccountId = acc.Id
        );
        insert c;
        
        
        // Create File
        ContentVersion cv = new ContentVersion(
            Title = 'TestPDF',
            PathOnClient = 'TestPDF.pdf',
            VersionData = Blob.valueOf('Test File Body'),
            IsMajorVersion = true
        );
        insert cv;
        
        Id docId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ].ContentDocumentId;
        
        
        // Link File to Case
        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = c.Id,
            ShareType = 'V'
        );
        insert link;
        
        
        // Set Callout Mock
        Test.setMock(HttpCalloutMock.class, new MetriportMock());
        
        Test.startTest();
        
        String result = CaseMetriportController.sendCaseFiles(c.Id);
        
        Test.stopTest();
        
        
        System.assertEquals(
            'Pdf Sent Successfully To Metriport',
            result
        );
        
        
        // Verify Case checkbox updated
        Case updatedCase = [
            SELECT Send_File_To_Metriport__c
            FROM Case
            WHERE Id = :c.Id
        ];
        
        System.assertEquals(true, updatedCase.Send_File_To_Metriport__c);
    }
}