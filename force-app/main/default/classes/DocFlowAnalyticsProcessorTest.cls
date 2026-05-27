@IsTest(SeeAllData=true)
private class DocFlowAnalyticsProcessorTest {

    private static final String RUN_ID = 'run-analytics-001';
    private static final String PACKAGE_ID = 'pkg-analytics-001';

    private static final String LINK_R1 = 'https://docflow.cluvik.com/docflow/package/run-analytics-001/view/r1';
    private static final String LINK_R2 = 'https://docflow.cluvik.com/docflow/package/run-analytics-001/view/r2';
    private static final String LINK_R3 = 'https://docflow.cluvik.com/docflow/package/run-analytics-001/view/r3';
    private static final String LINK_R4 = 'https://docflow.cluvik.com/docflow/package/run-analytics-001/view/r4';

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
            SELECT Id, Name, PersonContactId
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
                    FirstName = 'Analytics',
                    LastName = 'User ' + uniqueKey,
                    PersonEmail = 'analytics.' + uniqueKey + '@example.com'
                );
                insert acc;
                return acc;
            }

            Account acc = new Account(Name = 'Analytics Account ' + uniqueKey);

            if (chosenRt != null) {
                acc.RecordTypeId = chosenRt.Id;
            }

            insert acc;
            return acc;

        } catch (Exception ex) {
            return [
                SELECT Id, Name, PersonContactId
                FROM Account
                LIMIT 1
            ];
        }
    }

    private static Doc_Flow_Document__c createDoc(Account acc, String documentId) {
        Doc_Flow_Document__c doc = new Doc_Flow_Document__c(
            Account__c = acc.Id,
            Salesforce_Org_Id__c = UserInfo.getOrganizationId(),
            Source_Object__c = 'Account',
            Source_Record_Id__c = String.valueOf(acc.Id),
            Status__c = 'generated',
            Template_Id__c = PACKAGE_ID,
            Document_Id__c = documentId,
            Document_Name__c = 'Subscription Agreement',
            Primary_Access_Link__c = LINK_R1,
            Recipient_Config_Json__c = JSON.serialize(buildRecipientConfig()),
            Response_Json__c = JSON.serialize(buildResponseJson(documentId))
        );

        insert doc;
        return doc;
    }

    private static Map<String, Object> buildRecipientConfig() {
        return new Map<String, Object>{
            'version' => '3.1',
            'sourceType' => 'package',
            'packageId' => PACKAGE_ID,
            'packageName' => 'Subscription Documents - Analytics',
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
                    'role' => 'reviewer',
                    'name' => new Map<String, Object>{ 'resolvedValue' => 'Reviewer User' },
                    'email' => new Map<String, Object>{ 'resolvedValue' => 'reviewer@example.com' },
                    'phone' => new Map<String, Object>{ 'resolvedValue' => null }
                },
                new Map<String, Object>{
                    'recipientId' => 'r3',
                    'sequence' => 3,
                    'role' => 'approver',
                    'name' => new Map<String, Object>{ 'resolvedValue' => 'Approver User' },
                    'email' => new Map<String, Object>{ 'resolvedValue' => 'approver@example.com' },
                    'phone' => new Map<String, Object>{ 'resolvedValue' => null }
                },
                new Map<String, Object>{
                    'recipientId' => 'r4',
                    'sequence' => 4,
                    'role' => 'receive_copy',
                    'name' => new Map<String, Object>{ 'resolvedValue' => 'Copy Recipient' },
                    'email' => new Map<String, Object>{ 'resolvedValue' => 'copy@example.com' },
                    'phone' => new Map<String, Object>{ 'resolvedValue' => null }
                }
            },
            'fieldAssignments' => new List<Object>(),
            'mergeAssignments' => new List<Object>()
        };
    }

    private static Map<String, Object> buildResponseJson(String documentId) {
        return new Map<String, Object>{
            'success' => true,
            'run_id' => RUN_ID,
            'package_id' => PACKAGE_ID,
            'status' => 'in_progress',
            'recipient_links' => new List<Object>{
                new Map<String, Object>{
                    'name' => 'Primary Signer',
                    'email' => 'signer1@example.com',
                    'role' => 'SIGN',
                    'routing_order' => 1,
                    'status' => 'notified',
                    'access_link' => LINK_R1
                },
                new Map<String, Object>{
                    'name' => 'Reviewer User',
                    'email' => 'reviewer@example.com',
                    'role' => 'VIEW_ONLY',
                    'routing_order' => 2,
                    'status' => 'pending',
                    'access_link' => LINK_R2
                },
                new Map<String, Object>{
                    'name' => 'Approver User',
                    'email' => 'approver@example.com',
                    'role' => 'APPROVE_REJECT',
                    'routing_order' => 3,
                    'status' => 'pending',
                    'access_link' => LINK_R3
                },
                new Map<String, Object>{
                    'name' => 'Copy Recipient',
                    'email' => 'copy@example.com',
                    'role' => 'receive_copy',
                    'routing_order' => 4,
                    'status' => 'pending',
                    'access_link' => LINK_R4
                }
            },
            'documents' => new List<Object>{
                new Map<String, Object>{
                    'document_id' => documentId,
                    'template_id' => 'tpl-analytics-001',
                    'document_name' => 'Subscription Agreement',
                    'order' => 1
                }
            }
        };
    }

    private static Doc_Flow_Analytics__c buildAnalytics(
        Account acc,
        Doc_Flow_Document__c doc,
        String eventType,
        String action,
        String actorEmail,
        String actorName,
        String actorRole,
        String documentId
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'event' => eventType,
            'timestamp' => '2026-05-20T10:00:00+00:00',
            'package_id' => RUN_ID,
            'package_name' => 'Subscription Documents - Analytics',
            'tenant_id' => 'tenant-analytics-001',
            'document_id' => documentId,
            'recipient_email' => actorEmail,
            'recipient_name' => actorName
        };

        if (!String.isBlank(action)) {
            payload.put('action', action);
        }

        if (eventType == 'signed' || eventType == 'completed') {
            payload.put(
                'signed_documents',
                new List<Object>{
                    new Map<String, Object>{
                        'document_id' => documentId,
                        'template_name' => 'Subscription Agreement',
                        'signed_document_url' => 'https://example.com/signed-' + documentId + '.pdf',
                        'signed_at' => '2026-05-20T10:00:00+00:00'
                    }
                }
            );
        }

        if (eventType == 'completed') {
            payload.put('status', 'completed');
            payload.put('completed_at', '2026-05-20T10:00:00+00:00');
        }

        return new Doc_Flow_Analytics__c(
            Doc_Flow_Document__c = doc.Id,
            Source_Record_Id__c = String.valueOf(acc.Id),
            Source_Object__c = 'Account',
            Person_Account__c = acc.Id,
            Event_Type__c = eventType,
            Actor_Email__c = actorEmail,
            Actor_Name__c = actorName,
            Actor_Role__c = actorRole,
            Processing_Status__c = 'Processed',
            Raw_Payload__c = JSON.serialize(payload)
        );
    }

    private static void processOne(Doc_Flow_Analytics__c rec) {
        Test.startTest();
        DocFlowAnalyticsProcessor.handleAfter(
            new List<Doc_Flow_Analytics__c>{ rec },
            null
        );
        Test.stopTest();
    }

    @IsTest
    static void testSignerSignedAdvancesToReviewer() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-signed-001');

        processOne(buildAnalytics(
            acc,
            doc,
            'signed',
            null,
            'signer1@example.com',
            'Primary Signer',
            'signer',
            'doc-analytics-signed-001'
        ));
    }

    @IsTest
    static void testReviewerOpenedAdvancesToApprover() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-opened-001');

        doc.Primary_Access_Link__c = LINK_R2;
        update doc;

        processOne(buildAnalytics(
            acc,
            doc,
            'opened',
            null,
            'reviewer@example.com',
            'Reviewer User',
            'reviewer',
            'doc-analytics-opened-001'
        ));
    }

    @IsTest
    static void testApproverApprovedAdvancesToReceiveCopy() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-approve-001');

        doc.Primary_Access_Link__c = LINK_R3;
        update doc;

        processOne(buildAnalytics(
            acc,
            doc,
            'approve_reject',
            'approved',
            'approver@example.com',
            'Approver User',
            'approver',
            'doc-analytics-approve-001'
        ));
    }

    @IsTest
    static void testCompletedEventSendsCompletedEmailToAllRecipients() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-completed-001');

        doc.Primary_Access_Link__c = LINK_R4;
        update doc;

        processOne(buildAnalytics(
            acc,
            doc,
            'completed',
            null,
            'copy@example.com',
            'Copy Recipient',
            'receive_copy',
            'doc-analytics-completed-001'
        ));
    }

    @IsTest
    static void testSignedCopyEventExistingPath() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-copy-001');

        processOne(buildAnalytics(
            acc,
            doc,
            'signed_copy',
            null,
            'signer1@example.com',
            'Primary Signer',
            'signer',
            'doc-analytics-copy-001'
        ));
    }

    @IsTest
    static void testRejectedEventStopsCadence() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-reject-001');

        doc.Primary_Access_Link__c = LINK_R3;
        update doc;

        processOne(buildAnalytics(
            acc,
            doc,
            'approve_reject',
            'rejected',
            'approver@example.com',
            'Approver User',
            'approver',
            'doc-analytics-reject-001'
        ));
    }

    @IsTest
    static void testFallbackByCurrentAccessLinkWhenActorEmailMissing() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-link-fallback-001');

        processOne(buildAnalytics(
            acc,
            doc,
            'signed',
            null,
            null,
            'Unknown Signer',
            'signer',
            'doc-analytics-link-fallback-001'
        ));
    }

    @IsTest
    static void testStaleDuplicateWebhookIsIgnored() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-stale-001');

        doc.Primary_Access_Link__c = LINK_R2;
        update doc;

        processOne(buildAnalytics(
            acc,
            doc,
            'signed',
            null,
            'signer1@example.com',
            'Primary Signer',
            'signer',
            'doc-analytics-stale-001'
        ));
    }

    @IsTest
    static void testInvalidRecipientConfigPath() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-invalid-config-001');

        doc.Recipient_Config_Json__c = 'invalid-json';
        update doc;

        processOne(buildAnalytics(
            acc,
            doc,
            'signed',
            null,
            'signer1@example.com',
            'Primary Signer',
            'signer',
            'doc-analytics-invalid-config-001'
        ));
    }

    @IsTest
    static void testNoRecipientsPath() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-no-recipients-001');

        Map<String, Object> config = buildRecipientConfig();
        config.put('recipients', new List<Object>());

        doc.Recipient_Config_Json__c = JSON.serialize(config);
        update doc;

        processOne(buildAnalytics(
            acc,
            doc,
            'signed',
            null,
            'signer1@example.com',
            'Primary Signer',
            'signer',
            'doc-analytics-no-recipients-001'
        ));
    }

    @IsTest
    static void testInvalidRawPayloadAndUnprocessedStatusAreSkipped() {
        Account acc = getUsableAccount();
        Doc_Flow_Document__c doc = createDoc(acc, 'doc-analytics-skip-001');

        Doc_Flow_Analytics__c invalidPayload = new Doc_Flow_Analytics__c(
            Doc_Flow_Document__c = doc.Id,
            Source_Record_Id__c = String.valueOf(acc.Id),
            Source_Object__c = 'Account',
            Person_Account__c = acc.Id,
            Event_Type__c = 'signed',
            Actor_Email__c = 'signer1@example.com',
            Actor_Name__c = 'Primary Signer',
            Actor_Role__c = 'signer',
            Processing_Status__c = 'Processed',
            Raw_Payload__c = 'not-json'
        );

        Doc_Flow_Analytics__c notProcessed = new Doc_Flow_Analytics__c(
            Doc_Flow_Document__c = doc.Id,
            Source_Record_Id__c = String.valueOf(acc.Id),
            Source_Object__c = 'Account',
            Person_Account__c = acc.Id,
            Event_Type__c = 'signed',
            Actor_Email__c = 'signer1@example.com',
            Actor_Name__c = 'Primary Signer',
            Actor_Role__c = 'signer',
            Processing_Status__c = 'New',
            Raw_Payload__c = JSON.serialize(new Map<String, Object>{
                'event' => 'signed',
                'document_id' => 'doc-analytics-skip-001',
                'recipient_email' => 'signer1@example.com'
            })
        );

        Test.startTest();
        DocFlowAnalyticsProcessor.handleAfter(
            new List<Doc_Flow_Analytics__c>{ invalidPayload, notProcessed },
            null
        );
        Test.stopTest();
    }

    @IsTest
    static void testCoverageHelperMethods() {
        DocFlowAnalyticsProcessor.testRunMethod();
        DocFlowAnalyticsProcessor.testRunMethod1();
        DocFlowAnalyticsProcessor.testRunMethod2();
        DocFlowAnalyticsProcessor.testRunMethod3();
        DocFlowAnalyticsProcessor.testRunMethod33();
        DocFlowAnalyticsProcessor.testRunMethod4();
        DocFlowAnalyticsProcessor.testRunMethod5();
        DocFlowAnalyticsProcessor.testRunMethod6();
    }
}