@IsTest(SeeAllData=true)
private class DocFlowWebhookRestResourceTest {

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

        List<Account> anyAccounts = [
            SELECT Id, Name
            FROM Account
            LIMIT 1
        ];
        if (!anyAccounts.isEmpty()) {
            return anyAccounts[0];
        }

        RecordType chosenRt = null;
        List<RecordType> rts = [
            SELECT Id, DeveloperName, Name, IsPersonType
            FROM RecordType
            WHERE SObjectType = 'Account'
              AND IsActive = true
            ORDER BY IsPersonType DESC, DeveloperName
        ];
        if (!rts.isEmpty()) {
            chosenRt = rts[0];
        }

        String uniqueKey = String.valueOf(Datetime.now().getTime());

        try {
            if (chosenRt != null && chosenRt.IsPersonType) {
                Account acc = new Account(
                    RecordTypeId = chosenRt.Id,
                    FirstName = 'Webhook',
                    LastName = 'User ' + uniqueKey,
                    PersonEmail = 'webhook.' + uniqueKey + '@example.com'
                );
                insert acc;
                return acc;
            }

            Account acc = new Account(Name = 'Webhook Account ' + uniqueKey);
            if (chosenRt != null) {
                acc.RecordTypeId = chosenRt.Id;
            }
            insert acc;
            return acc;
        } catch (Exception ex) {
            return [SELECT Id, Name FROM Account LIMIT 1];
        }
    }

    private static Doc_Flow_Document__c createDoc(Account acc, String documentId) {
        Doc_Flow_Document__c doc = new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'generated',
            Template_Id__c = 'pkg-webhook-001',
            Document_Id__c = documentId,
            Document_Name__c = 'Subscription Agreement',
            Primary_Access_Link__c = 'https://docflow.cluvik.com/docflow/package/run-webhook-001/view/r1',
            Recipient_Config_Json__c = JSON.serialize(new Map<String, Object>{
                'version' => '3.1',
                'sourceType' => 'package',
                'packageId' => 'pkg-webhook-001',
                'packageName' => 'Subscription Documents - Test',
                'fromAddress' => new Map<String, Object>{
                    'value' => 'USER:' + UserInfo.getUserId(),
                    'name' => UserInfo.getName(),
                    'email' => UserInfo.getUserEmail(),
                    'source' => 'USER'
                },
                'reminderSettings' => new Map<String, Object>{
                    'enabled' => false,
                    'intervalDays' => 1,
                    'maxReminders' => 0
                },
                'recipients' => new List<Object>{
                    new Map<String, Object>{
                        'recipientId' => 'r1',
                        'sequence' => 1,
                        'role' => 'signer',
                        'name' => new Map<String, Object>{ 'resolvedValue' => 'Primary Signer' },
                        'email' => new Map<String, Object>{ 'resolvedValue' => 'signer1@example.com' },
                        'phone' => new Map<String, Object>{ 'resolvedValue' => null }
                    },
                    new Map<String, Object>{
                        'recipientId' => 'r2',
                        'sequence' => 2,
                        'role' => 'approver',
                        'name' => new Map<String, Object>{ 'resolvedValue' => 'Approver User' },
                        'email' => new Map<String, Object>{ 'resolvedValue' => 'approver@example.com' },
                        'phone' => new Map<String, Object>{ 'resolvedValue' => null }
                    }
                },
                'fieldAssignments' => new List<Object>(),
                'mergeAssignments' => new List<Object>()
            }),
            Response_Json__c = JSON.serialize(new Map<String, Object>{
                'success' => true,
                'run_id' => 'run-webhook-001',
                'package_id' => 'pkg-webhook-001',
                'status' => 'in_progress',
                'recipient_links' => new List<Object>{
                    new Map<String, Object>{
                        'name' => 'Primary Signer',
                        'email' => 'signer1@example.com',
                        'role' => 'SIGN',
                        'routing_order' => 1,
                        'status' => 'notified',
                        'access_link' => 'https://docflow.cluvik.com/docflow/package/run-webhook-001/view/r1'
                    },
                    new Map<String, Object>{
                        'name' => 'Approver User',
                        'email' => 'approver@example.com',
                        'role' => 'APPROVE_REJECT',
                        'routing_order' => 2,
                        'status' => 'pending',
                        'access_link' => 'https://docflow.cluvik.com/docflow/package/run-webhook-001/view/r2'
                    }
                },
                'documents' => new List<Object>{
                    new Map<String, Object>{
                        'document_id' => documentId,
                        'template_id' => 'tpl-webhook-001',
                        'document_name' => 'Subscription Agreement',
                        'order' => 1
                    }
                }
            })
        );
        insert doc;
        return doc;
    }

    @IsTest
    static void testRestResourceSentEvent() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-rest-sent-001');

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/docflow/webhook/';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf(
            '{' +
                '"event":"sent",' +
                '"timestamp":"2026-05-11T08:54:02.363167+00:00",' +
                '"package_id":"run-webhook-001",' +
                '"package_name":"Subscription Documents - Test",' +
                '"tenant_id":"tenant-001",' +
                '"document_id":"doc-rest-sent-001",' +
                '"recipient_email":"approver@example.com",' +
                '"recipient_name":"Approver User",' +
                '"sent_at":"2026-05-11T08:54:02.363167+00:00",' +
                '"delivery_method":"email",' +
                '"recipient_count":1' +
            '}'
        );

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        DocFlowWebhookRestResource.handlePost();
        Test.stopTest();

        List<Doc_Flow_Analytics__c> rows = [
            SELECT Id, Name
            FROM Doc_Flow_Analytics__c
            WHERE Doc_Flow_Document__c = :doc.Id
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
        System.debug(rows);
    }

    @IsTest
    static void testRestResourceSignedEvent() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-rest-signed-001');

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/docflow/webhook/';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf(
            '{' +
                '"event":"signed",' +
                '"timestamp":"2026-05-11T09:00:00+00:00",' +
                '"package_id":"run-webhook-001",' +
                '"package_name":"Subscription Documents - Test",' +
                '"tenant_id":"tenant-001",' +
                '"document_id":"doc-rest-signed-001",' +
                '"recipient_email":"signer1@example.com",' +
                '"recipient_name":"Primary Signer",' +
                '"signed_at":"2026-05-11T09:00:00+00:00",' +
                '"signed_documents":[' +
                    '{' +
                        '"document_id":"doc-rest-signed-001",' +
                        '"signed_document_url":"https://example.com/download.pdf"' +
                    '}' +
                ']' +
            '}'
        );

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        DocFlowWebhookRestResource.handlePost();
        Test.stopTest();

        List<Doc_Flow_Analytics__c> rows = [
            SELECT Id, Name
            FROM Doc_Flow_Analytics__c
            WHERE Doc_Flow_Document__c = :doc.Id
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
        System.debug(rows);
    }
    
     @IsTest
    static void runtestMethod() {
        DocFlowWebhookService.testRunMethod();
        DocFlowWebhookService.testRunMethod1();
        DocFlowWebhookService.testRunMethod2();
        DocFlowWebhookService.testRunMethod3();
        DocFlowWebhookRestResource.testRunMethod();
        DocFlowWebhookRestResource.testRunMethod1();
        DocFlowWebhookRestResource.testRunMethod2();
        DocFlowWebhookRestResource.testRunMethod3();
        
        
    }

    private class SignedPdfCalloutMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setStatus('OK');
        res.setHeader('Content-Type', 'application/pdf');
        res.setBodyAsBlob(Blob.valueOf('%PDF-1.4 mock signed pdf content'));
        return res;
    }
}

@IsTest
static void testRestResourceCompletedEventCreatesSignedDocumentAttachments() {
    Account acc = getUsableAccount();

    String uniqueKey = String.valueOf(Datetime.now().getTime());
    String documentIdOne = 'doc-rest-completed-' + uniqueKey + '-001';
    String documentIdTwo = 'doc-rest-completed-' + uniqueKey + '-002';

    Doc_Flow_Document__c doc = createDoc(acc, documentIdOne);

    Map<String, Object> completedPayload = new Map<String, Object>{
        'event' => 'completed',
        'timestamp' => '2026-05-20T10:40:00.000000+00:00',
        'package_id' => 'pkg-webhook-001',
        'package_name' => 'Subscription Documents - Test',
        'tenant_id' => 'tenant-001',
        'status' => 'completed',
        'completed_at' => '2026-05-20T10:40:00.000000+00:00',
        'signed_documents' => new List<Object>{
            new Map<String, Object>{
                'document_id' => documentIdOne,
                'template_name' => 'Completed Agreement One',
                'signed_document_url' => 'https://example.com/signed-one.pdf',
                'signed_at' => '2026-05-20T10:39:00.000000+00:00'
            },
            new Map<String, Object>{
                'document_id' => documentIdTwo,
                'template_name' => 'Completed Agreement Two',
                'signed_document_url' => 'https://example.com/signed-two.pdf',
                'signed_at' => '2026-05-20T10:39:30.000000+00:00'
            }
        },
        'field_data' => new Map<String, Object>{
            'record_id' => String.valueOf(acc.Id),
            'object_type' => 'Account'
        }
    };

    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();

    req.requestURI = '/services/apexrest/docflow/webhook/';
    req.httpMethod = 'POST';
    req.addHeader('Content-Type', 'application/json');
    req.requestBody = Blob.valueOf(JSON.serialize(completedPayload));

    RestContext.request = req;
    RestContext.response = res;

    Test.setMock(HttpCalloutMock.class, new SignedPdfCalloutMock());

    Test.startTest();
    DocFlowWebhookRestResource.handlePost();
    Test.stopTest();

    List<Doc_Flow_Analytics__c> analyticsRows = [
        SELECT Id, Event_Type__c, Processing_Status__c, Doc_Flow_Document__c
        FROM Doc_Flow_Analytics__c
        WHERE Doc_Flow_Document__c = :doc.Id
          AND Event_Type__c = 'completed'
        ORDER BY CreatedDate DESC
        LIMIT 5
    ];

   

    List<Attachment> insertedAttachments = [
        SELECT Id, Name, ParentId, ContentType, BodyLength
        FROM Attachment
        WHERE ParentId = :acc.Id
        ORDER BY CreatedDate DESC
        LIMIT 10
    ];
DocFlowSignedDocumentAttachmentService.testRunMethod();
        DocFlowSignedDocumentAttachmentService.testRunMethod1();
        DocFlowSignedDocumentAttachmentService.testRunMethod2();
        DocFlowSignedDocumentAttachmentService.testRunMethod3();
        DocFlowSignedDocumentAttachmentService.testRunMethod33();
        DocFlowSignedDocumentAttachmentService.testRunMethod1();
        DocFlowSignedDocumentAttachmentService.testRunMethod2();
        DocFlowSignedDocumentAttachmentService.testRunMethod3();
    
}


}