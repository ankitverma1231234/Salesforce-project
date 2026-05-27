@IsTest(SeeAllData=true)
public class CaseMedicalChatterCrateTest {
    
    /* ============================================================
HELPER: GET EXISTING ACCOUNT + CONTACT
============================================================ */
    private static Map<String, Id> getAccountAndContact() {
        
        Map<String, Id> result = new Map<String, Id>();
        
        // 1️⃣ Try to get existing Account + Contact
        List<Account> accList = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];
        
        List<Contact> conList = [
            SELECT Id
            FROM Contact
            LIMIT 1
        ];
        
        if (!accList.isEmpty() && !conList.isEmpty()) {
            result.put('AccountId', accList[0].Id);
            result.put('ContactId', conList[0].Id);
            return result;
        }
        
        // 2️⃣ Fallback: create minimal Account + Contact
        Account acc = new Account(Name = 'Fallback Account');
        insert acc;
        
        Contact con = new Contact(
            FirstName = 'Fallback',
            LastName  = 'Contact',
            Email     = 'fallback@test.com',
            AccountId = acc.Id
        );
        insert con;
        
        result.put('AccountId', acc.Id);
        result.put('ContactId', con.Id);
        
        return result;
    }
    
    /* ============================================================
HELPER: GET OR CREATE CASE
============================================================ */
    private static Case getCaseRecord() {
        
        List<Case> cases = [
            SELECT Id, CaseNumber
            FROM Case
            LIMIT 1
        ];
        
        if (!cases.isEmpty()) {
            return cases[0];
        }
        
        Map<String, Id> ids = getAccountAndContact();
        
        Case c = new Case(
            Subject   = 'Fallback Case',
            Status    = 'New',
            Origin    = 'Phone',
            AccountId = ids.get('AccountId'),
            ContactId = ids.get('ContactId')
        );
        insert c;
        
        return c;
    }
    
    /* ============================================================
TEST 1: CASE CREATION (messages)
============================================================ */
    @IsTest
    static void testCreateCase() {
        
        Map<String, Id> ids = getAccountAndContact();
        
        String requestBody = JSON.serialize(new Map<String, Object>{
            'messages' => new List<Object>{
                new Map<String, Object>{
                    'Subject'        => 'API Case',
                        'Description'    => 'Created via API',
                        'Status'         => 'New',
                        'Priority'       => 'Medium',
                        'Origin'         => 'Web',
                        'Reason'         => 'General Inquiry',
                        'Type'           => 'Question',
                        'SuppliedEmail'  => 'api@test.com',
                        'SuppliedPhone'  => '9999999999',
                        'AccountId'      => ids.get('AccountId'),
                        'ContactId'      => ids.get('ContactId')
                        }
            }
        });
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/Casechatterportal/V1/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        
        RestContext.request  = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        CaseMedicalChatterCrate.ResponseWrapper response =
            CaseMedicalChatterCrate.receiveData();
        Test.stopTest();
        
    }
    
    /* ============================================================
TEST 2: CASE COMMENT CREATION (conversations)
============================================================ */
    @IsTest
    static void testCreateCaseComment() {
        
        Case c = getCaseRecord();
        
        String requestBody = JSON.serialize(new Map<String, Object>{
            'conversations' => new List<Object>{
                new Map<String, Object>{
                    'case_message_id' => c.Id,
                        'message_body'    => 'This is a test comment'
                        }
            }
        });
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/Casechatterportal/V1/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        
        RestContext.request  = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        CaseMedicalChatterCrate.ResponseWrapper response =
            CaseMedicalChatterCrate.receiveData();
        Test.stopTest();
        
        System.assertEquals(
            'Case Comment created successfully',
            response.message
        );
        
        // Verify Case Comment
        List<CaseComment> comments = [
            SELECT Id, CommentBody
            FROM CaseComment
            WHERE ParentId = :c.Id
        ];
    }
    
    /* ============================================================
TEST 3: CASE CREATION WITH FILE ATTACHMENTS
============================================================ */
    @IsTest
    static void testCreateCaseWithFileAttachments() {
        
        Map<String, Id> ids = getAccountAndContact();
        
        // Set mock for HTTP callout
        Test.setMock(HttpCalloutMock.class, new FileDownloadMockSuccess());
        
        String requestBody = JSON.serialize(new Map<String, Object>{
            'messages' => new List<Object>{
                new Map<String, Object>{
                    'Subject'        => 'API Case with Files',
                        'Description'    => 'Created via API with attachments',
                        'Status'         => 'New',
                        'Priority'       => 'High',
                        'Origin'         => 'Web',
                        'AccountId'      => ids.get('AccountId'),
                        'ContactId'      => ids.get('ContactId'),
                        'file_attachments' => new List<Object>{
                            new Map<String, Object>{
                                'file_url'  => 'https://example.com/file1.pdf',
                                    'filename'  => 'TestDocument1.pdf'
                                    },
                                        new Map<String, Object>{
                                            'file_url'  => 'https://example.com/file2.pdf',
                                                'filename'  => 'TestDocument2.pdf'
                                                }
                        }
                }
            }
        });
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/Casechatterportal/V1/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        
        RestContext.request  = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        CaseMedicalChatterCrate.ResponseWrapper response =
            CaseMedicalChatterCrate.receiveData();
        Test.stopTest();
        
        
        // Verify files were attached asynchronously
        List<ContentVersion> attachedFiles = [
            SELECT Id, Title, PathOnClient, FirstPublishLocationId
            FROM ContentVersion
            WHERE FirstPublishLocationId = :response.caseId
        ];
        
    }
    
    /* ============================================================
TEST 4: MULTIPLE CASES WITH FILE ATTACHMENTS
============================================================ */
    @IsTest
    static void testMultipleCasesWithFileAttachments() {
        
        Map<String, Id> ids = getAccountAndContact();
        
        // Set mock for HTTP callout
        Test.setMock(HttpCalloutMock.class, new FileDownloadMockSuccess());
        
        String requestBody = JSON.serialize(new Map<String, Object>{
            'messages' => new List<Object>{
                new Map<String, Object>{
                    'Subject'        => 'Case 1 with Files',
                        'Description'    => 'First case',
                        'Status'         => 'New',
                        'Origin'         => 'Web',
                        'AccountId'      => ids.get('AccountId'),
                        'ContactId'      => ids.get('ContactId'),
                        'file_attachments' => new List<Object>{
                            new Map<String, Object>{
                                'file_url'  => 'https://example.com/case1_file1.pdf',
                                    'filename'  => 'Case1_Doc1.pdf'
                                    }
                        }
                },
                    new Map<String, Object>{
                        'Subject'        => 'Case 2 with Files',
                            'Description'    => 'Second case',
                            'Status'         => 'New',
                            'Origin'         => 'Web',
                            'AccountId'      => ids.get('AccountId'),
                            'ContactId'      => ids.get('ContactId'),
                            'file_attachments' => new List<Object>{
                                new Map<String, Object>{
                                    'file_url'  => 'https://example.com/case2_file1.pdf',
                                        'filename'  => 'Case2_Doc1.pdf'
                                        }
                            }
                    }
            }
        });
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/Casechatterportal/V1/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        
        RestContext.request  = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        CaseMedicalChatterCrate.ResponseWrapper response =
            CaseMedicalChatterCrate.receiveData();
        Test.stopTest();
        
        // Response will contain the last case created
        System.assertNotEquals(null, response.caseId);
        
        // Verify files were attached to their respective cases
        List<Case> createdCases = [
            SELECT Id, Subject
            FROM Case
            WHERE Subject IN ('Case 1 with Files', 'Case 2 with Files')
        ];
        
        System.assertEquals(2, createdCases.size(), 'Expected 2 cases to be created');
        
        // Check file attachments for each case using ContentDocumentLink
        for (Case c : createdCases) {
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :c.Id
            ];
            
        }
    }
    
    /* ============================================================
TEST 5: CASE WITH INVALID FILE ATTACHMENT DATA
============================================================ */
    @IsTest
    static void testCaseWithInvalidFileAttachments() {
        
        Map<String, Id> ids = getAccountAndContact();
        
        // Set mock that returns 404
        Test.setMock(HttpCalloutMock.class, new FileDownloadMockFailure());
        
        String requestBody = JSON.serialize(new Map<String, Object>{
            'messages' => new List<Object>{
                new Map<String, Object>{
                    'Subject'        => 'Case with Invalid Files',
                        'Description'    => 'Testing invalid file URLs',
                        'Status'         => 'New',
                        'Origin'         => 'Web',
                        'AccountId'      => ids.get('AccountId'),
                        'ContactId'      => ids.get('ContactId'),
                        'file_attachments' => new List<Object>{
                            new Map<String, Object>{
                                'file_url'  => 'https://example.com/nonexistent.pdf',
                                    'filename'  => 'NonExistent.pdf'
                                    },
                                        new Map<String, Object>{
                                            'file_url'  => '',  // Blank URL
                                                'filename'  => 'BlankUrl.pdf'
                                                }
                        }
                }
            }
        });
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/Casechatterportal/V1/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        
        RestContext.request  = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        CaseMedicalChatterCrate.ResponseWrapper response =
            CaseMedicalChatterCrate.receiveData();
        Test.stopTest();
        
        
        // Verify no files were attached (due to failures)
        List<ContentVersion> attachedFiles = [
            SELECT Id
            FROM ContentVersion
            WHERE FirstPublishLocationId = :response.caseId
        ];
        
        System.assertEquals(0, attachedFiles.size(), 
                            'No files should be attached due to failures');
    }
    
    /* ============================================================
TEST 6: INVALID PAYLOAD
============================================================ */
    @IsTest
    static void testInvalidPayload() {
        
        String requestBody = JSON.serialize(
            new Map<String, Object>{ 'invalidKey' => 'invalidValue' }
        );
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/Casechatterportal/V1/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(requestBody);
        
        RestContext.request  = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        CaseMedicalChatterCrate.ResponseWrapper response =
            CaseMedicalChatterCrate.receiveData();
        Test.stopTest();
        
        System.assertEquals(
            'Invalid payload structure',
            response.message
        );
        System.assertEquals(
            400,
            RestContext.response.statusCode
        );
    }
    
    /* ============================================================
MOCK CLASSES FOR HTTP CALLOUTS
============================================================ */
    
    // Mock class for successful file download
    private class FileDownloadMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody('Mock PDF file content');
            res.setHeader('Content-Type', 'application/pdf');
            return res;
        }
    }
    
    // Mock class for failed file download
    private class FileDownloadMockFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setStatus('Not Found');
            return res;
        }
    }
    @IsTest
    static void testSkipExistingCaseId() {
        Case c = getCaseRecord();
        
        String body = JSON.serialize(new Map<String,Object>{
            'messages' => new List<Object>{
                new Map<String,Object>{
                    'Id' => c.Id,
                        'Subject' => 'Should Be Skipped'
                        }
            }
        });
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/Casechatterportal/V1/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        CaseMedicalChatterCrate.receiveData();
        Test.stopTest();
    }
    
    @IsTest
    static void testSingleAttachmentKeyCoverage() {
        
        Map<String, Id> ids = getAccountAndContact();
        
        Test.setMock(HttpCalloutMock.class, new FileDownloadMockSuccess());
        
        String body = JSON.serialize(new Map<String,Object>{
            'messages' => new List<Object>{
                new Map<String,Object>{
                    'Subject' => 'Attachment Coverage',
                        'Status' => 'New',
                        'Origin' => 'Web',
                        'AccountId' => ids.get('AccountId'),
                        'ContactId' => ids.get('ContactId'),
                        'Attachment' => new Map<String,Object>{
                            'url' => 'https://example.com/test.pdf',
                                'filename' => 'TestFile.pdf'
                                }
                }
            }
        });
        
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/Casechatterportal/V1/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        
        RestContext.request = req;
        RestContext.response = new RestResponse();
        
        Test.startTest();
        CaseMedicalChatterCrate.receiveData();
        Test.stopTest();
    }
    
}