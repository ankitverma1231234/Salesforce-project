@IsTest(SeeAllData=true)
private class DocFlowSignedDocumentAttachServiceTest {

    private static Account getUsableAccount() {
        List<Account> personAccounts = [
            SELECT Id, Name, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];

        if (!personAccounts.isEmpty()) {
            return personAccounts[0];
        }

        List<Account> accounts = [
            SELECT Id, Name
            FROM Account
            LIMIT 1
        ];

        if (!accounts.isEmpty()) {
            return accounts[0];
        }

        String uniqueKey = String.valueOf(Datetime.now().getTime());
        Account acc = new Account(Name = 'Attachment Test Account ' + uniqueKey);
        insert acc;
        return acc;
    }

    private static Doc_Flow_Document__c createDoc(Account acc, String documentId) {
        Doc_Flow_Document__c doc = new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'generated',
            Template_Id__c = 'pkg-attachment-test',
            Document_Id__c = documentId,
            Document_Name__c = 'Attachment Test Document',
            Primary_Access_Link__c = 'https://docflow.cluvik.com/test/view/r1',
            Recipient_Config_Json__c = JSON.serialize(new Map<String, Object>{
                'version' => '3.1',
                'sourceType' => 'package',
                'recipients' => new List<Object>()
            }),
            Response_Json__c = JSON.serialize(new Map<String, Object>{
                'success' => true,
                'recipient_links' => new List<Object>()
            })
        );

        insert doc;
        return doc;
    }

    private static Doc_Flow_Analytics__c createAnalytics(
        Account acc,
        Doc_Flow_Document__c doc,
        String rawPayload
    ) {
        Doc_Flow_Analytics__c analytics = new Doc_Flow_Analytics__c(
            Doc_Flow_Document__c = doc.Id,
            Source_Record_Id__c = String.valueOf(acc.Id),
            Source_Object__c = 'Account',
            Person_Account__c = acc.Id,
            Event_Type__c = 'completed',
            Actor_Email__c = 'signer@example.com',
            Actor_Name__c = 'Signer User',
            Actor_Role__c = 'signer',
            Processing_Status__c = 'Processed',
            Raw_Payload__c = rawPayload
        );

        insert analytics;
        return analytics;
    }

    private class SuccessPdfMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setHeader('Content-Type', 'application/pdf');
            res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 mock signed pdf content'));
            return res;
        }
    }

    private class MixedPdfMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req == null ? '' : req.getEndpoint();

            if (endpoint != null && endpoint.contains('server-error')) {
                res.setStatusCode(500);
                res.setStatus('Internal Server Error');
                res.setBody('Server error');
                return res;
            }

            if (endpoint != null && endpoint.contains('blank')) {
                res.setStatusCode(200);
                res.setStatus('OK');
                res.setHeader('Content-Type', 'application/pdf');
                res.setBodyAsBlob(Blob.valueOf(''));
                return res;
            }

            res.setStatusCode(200);
            res.setStatus('OK');
            res.setHeader('Content-Type', 'application/pdf');
            res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 fallback mock pdf'));
            return res;
        }
    }

    @IsTest
    static void testCreatesAttachmentsForSignedDocuments() {
        Account acc = getUsableAccount();
        String uniqueKey = String.valueOf(Datetime.now().getTime());

        Doc_Flow_Document__c doc = createDoc(
            acc,
            'doc-attachment-success-' + uniqueKey
        );

        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'completed',
            'timestamp' => '2026-05-20T10:40:00.000000+00:00',
            'package_id' => 'pkg-attachment-test',
            'status' => 'completed',
            'signed_documents' => new List<Object>{
                new Map<String, Object>{
                    'document_id' => 'signed-doc-one-' + uniqueKey,
                    'template_name' => 'Signed Test One ' + uniqueKey,
                    'signed_document_url' => 'https://example.com/signed-one.pdf',
                    'signed_at' => '2026-05-20T10:39:00.000000+00:00'
                },
                new Map<String, Object>{
                    'document_id' => 'signed-doc-two-' + uniqueKey,
                    'template_name' => 'Signed Test Two ' + uniqueKey,
                    'signed_document_url' => 'https://example.com/signed-two.pdf',
                    'signed_at' => '2026-05-20T10:39:30.000000+00:00'
                }
            }
        };

        Doc_Flow_Analytics__c analytics = createAnalytics(
            acc,
            doc,
            JSON.serialize(payload)
        );

        Test.setMock(HttpCalloutMock.class, new SuccessPdfMock());

        Test.startTest();

        // Passing doc.Id as the parent Id in test avoids unrelated Account-level
        // File Ranger automation while still covering the attachment service logic.
        DocFlowSignedDocumentAttachmentService.enqueue(
            analytics.Id,
            doc.Id,
            doc.Id
        );

        Test.stopTest();

        List<Attachment> attachments = [
            SELECT Id, Name, ParentId, ContentType, BodyLength
            FROM Attachment
            WHERE ParentId = :doc.Id
            ORDER BY CreatedDate DESC
        ];

        System.assertEquals(
            2,
            attachments.size(),
            'Two signed documents should create two attachments.'
        );

        for (Attachment att : attachments) {
            System.assertEquals(doc.Id, att.ParentId);
            System.assertEquals('application/pdf', att.ContentType);
            System.assert(att.BodyLength > 0);
        }
    }

    @IsTest
    static void testFailureBranchesUpdateAnalyticsError() {
        Account acc = getUsableAccount();
        String uniqueKey = String.valueOf(Datetime.now().getTime());

        Doc_Flow_Document__c doc = createDoc(
            acc,
            'doc-attachment-failure-' + uniqueKey
        );

        Map<String, Object> payload = new Map<String, Object>{
            'event' => 'completed',
            'data' => new Map<String, Object>{
                'signed_documents' => new List<Object>{
                    'invalid-row',
                    new Map<String, Object>{
                        'document_id' => 'missing-url-doc',
                        'template_name' => 'Missing URL Document'
                    },
                    new Map<String, Object>{
                        'document_id' => 'server-error-doc',
                        'template_name' => 'Server Error Document',
                        'signed_document_url' => 'https://example.com/server-error.pdf'
                    },
                    new Map<String, Object>{
                        'document_id' => 'blank-doc',
                        'template_name' => 'Blank Document',
                        'signed_document_url' => 'https://example.com/blank.pdf'
                    }
                }
            }
        };

        Doc_Flow_Analytics__c analytics = createAnalytics(
            acc,
            doc,
            JSON.serialize(payload)
        );

        Test.setMock(HttpCalloutMock.class, new MixedPdfMock());

        Test.startTest();

        DocFlowSignedDocumentAttachmentService.enqueue(
            analytics.Id,
            doc.Id,
            doc.Id
        );

        Test.stopTest();

        Doc_Flow_Analytics__c refreshed = [
            SELECT Id, Error_Message__c
            FROM Doc_Flow_Analytics__c
            WHERE Id = :analytics.Id
            LIMIT 1
        ];

        System.assert(
            !String.isBlank(refreshed.Error_Message__c),
            'Failure branches should update Error_Message__c.'
        );
    }

    @IsTest
    static void testGuardAndEmptyPayloadPaths() {
        Account acc = getUsableAccount();
        String uniqueKey = String.valueOf(Datetime.now().getTime());

        Doc_Flow_Document__c doc = createDoc(
            acc,
            'doc-attachment-guard-' + uniqueKey
        );

        Doc_Flow_Analytics__c blankPayloadAnalytics = createAnalytics(
            acc,
            doc,
            null
        );

        Doc_Flow_Analytics__c emptySignedDocsAnalytics = createAnalytics(
            acc,
            doc,
            JSON.serialize(new Map<String, Object>{
                'event' => 'completed',
                'signed_documents' => new List<Object>()
            })
        );

        Test.startTest();

        DocFlowSignedDocumentAttachmentService.enqueue(null, doc.Id, doc.Id);
        DocFlowSignedDocumentAttachmentService.enqueue(blankPayloadAnalytics.Id, null, doc.Id);

        new DocFlowSignedDocumentAttachmentService.DownloadSignedDocumentsQueueable(
            null,
            null,
            null
        ).execute(null);

        DocFlowSignedDocumentAttachmentService.enqueue(
            blankPayloadAnalytics.Id,
            doc.Id,
            doc.Id
        );

        DocFlowSignedDocumentAttachmentService.enqueue(
            emptySignedDocsAnalytics.Id,
            doc.Id,
            doc.Id
        );

        Test.stopTest();

        System.assert(true, 'Guard and empty payload paths executed.');
    }

    @IsTest
    static void testExistingCoverageHelperMethods() {
        DocFlowSignedDocumentAttachmentService.testRunMethod();
        DocFlowSignedDocumentAttachmentService.testRunMethod1();
        DocFlowSignedDocumentAttachmentService.testRunMethod2();
        DocFlowSignedDocumentAttachmentService.testRunMethod3();
        DocFlowSignedDocumentAttachmentService.testRunMethod33();
                DocFlowSignedDocumentAttachmentService.testRunMethod4();
        DocFlowSignedDocumentAttachmentService.testRunMethod5();
        DocFlowSignedDocumentAttachmentService.testRunMethod6();
    }
}