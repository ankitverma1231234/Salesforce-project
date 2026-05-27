public with sharing class DocFlowSampleDataFactory {

    private static final String ANALYTICS_OBJECT = 'Doc_Flow_Analytics__c';
    private static final String DOCUMENT_OBJECT  = 'Doc_Flow_Document__c';
    private static final String RECIPIENT_OBJECT = 'Doc_Flow_Recipient_Link__c';

    private static final String TEMPLATE_ID = 'b8789bc6-a07b-4a8e-864e-d5270021b407';
    private static final String SOURCE_OBJECT = 'Account';
    private static final String STATIC_ROLE = 'signer';
    private static final Integer STATIC_ROUTING_ORDER = 1;

    public static void createAllForPersonAccount(Id personAccountId) {
        Account pa = getPersonAccount(personAccountId);
        createWebhookSamplesInternal(pa);
        createPublicLinkSamplesInternal(pa);
    }

    public static void createWebhookSamplesForPersonAccount(Id personAccountId) {
        Account pa = getPersonAccount(personAccountId);
        createWebhookSamplesInternal(pa);
    }

    public static void createPublicLinkSamplesForPersonAccount(Id personAccountId) {
        Account pa = getPersonAccount(personAccountId);
        createPublicLinkSamplesInternal(pa);
    }

    private static Account getPersonAccount(Id personAccountId) {
        Account pa = [
            SELECT Id, Name, Industry, PersonEmail, PersonContactId, IsPersonAccount
            FROM Account
            WHERE Id = :personAccountId
            LIMIT 1
        ];

        if (!pa.IsPersonAccount) {
            throw new AuraHandledException('The provided Id is not a Person Account.');
        }
        if (String.isBlank(pa.PersonEmail)) {
            throw new AuraHandledException('Person Account must have PersonEmail.');
        }
        return pa;
    }

    private static void createWebhookSamplesInternal(Account pa) {
        Schema.SObjectType analyticsType = Schema.getGlobalDescribe().get(ANALYTICS_OBJECT);
        if (analyticsType == null) {
            throw new AuraHandledException(ANALYTICS_OBJECT + ' was not found.');
        }

        List<SObject> analyticsRows = new List<SObject>();

        String recipientId = String.isBlank(pa.PersonContactId) ? (String) pa.Id : (String) pa.PersonContactId;
        Datetime nowGmt = System.now();

        // ------------------------------------------------------------
        // Document set 1 - happy path
        // ------------------------------------------------------------
        String docId1 = 'DOC-' + randomToken(12);
        String docName1 = 'Non-Disclosure Agreement - ' + pa.Name;
        String publicLink1 = 'http://localhost:3000/docflow/view/' + randomToken(48);
        String downloadUrl1 = 'https://api.example.com/documents/' + docId1 + '/download/final.pdf';

        Datetime created1 = nowGmt.addDays(-2);
        analyticsRows.add(buildWebhookAnalyticsRow(
            analyticsType, pa, recipientId,
            'evt_' + randomToken(18), 'document_sent', created1.addMinutes(5),
            docId1, docName1, 'sent', publicLink1, null, created1, null,
            false, 'sent', null, null,
            null
        ));

        analyticsRows.add(buildWebhookAnalyticsRow(
            analyticsType, pa, recipientId,
            'evt_' + randomToken(18), 'document_opened', created1.addMinutes(15),
            docId1, docName1, 'pending', publicLink1, null, created1, null,
            true, 'opened', null, null,
            buildAnalytics('192.168.1.10', 'Mozilla/5.0', 'desktop', 'Chrome', 'Windows')
        ));

        analyticsRows.add(buildWebhookAnalyticsRow(
            analyticsType, pa, recipientId,
            'evt_' + randomToken(18), 'document_viewed', created1.addMinutes(20),
            docId1, docName1, 'pending', publicLink1, null, created1, null,
            true, 'viewed', null, null,
            buildAnalytics('192.168.1.10', 'Mozilla/5.0', 'desktop', 'Chrome', 'Windows')
        ));

        Datetime signed1 = created1.addMinutes(35);
        analyticsRows.add(buildWebhookAnalyticsRow(
            analyticsType, pa, recipientId,
            'evt_' + randomToken(18), 'recipient_signed', signed1,
            docId1, docName1, 'completed', publicLink1, null, created1, signed1,
            true, 'signed', signed1, null,
            buildAnalytics('192.168.1.10', 'Mozilla/5.0', 'desktop', 'Chrome', 'Windows')
        ));

        analyticsRows.add(buildWebhookAnalyticsRow(
            analyticsType, pa, recipientId,
            'evt_' + randomToken(18), 'signed_copy_generated', signed1.addMinutes(2),
            docId1, docName1, 'completed', publicLink1, downloadUrl1, created1, signed1,
            false, 'signed', signed1, null,
            null
        ));

        // ------------------------------------------------------------
        // Document set 2 - declined
        // ------------------------------------------------------------
        String docId2 = 'DOC-' + randomToken(12);
        String docName2 = 'Care Coordination Consent - ' + pa.Name;
        String publicLink2 = 'http://localhost:3000/docflow/view/' + randomToken(48);

        Datetime created2 = nowGmt.addDays(-1);
        analyticsRows.add(buildWebhookAnalyticsRow(
            analyticsType, pa, recipientId,
            'evt_' + randomToken(18), 'document_sent', created2.addMinutes(5),
            docId2, docName2, 'sent', publicLink2, null, created2, null,
            false, 'sent', null, null,
            null
        ));

        Datetime declined2 = created2.addMinutes(25);
        analyticsRows.add(buildWebhookAnalyticsRow(
            analyticsType, pa, recipientId,
            'evt_' + randomToken(18), 'recipient_declined', declined2,
            docId2, docName2, 'declined', publicLink2, null, created2, null,
            true, 'declined', null, declined2,
            buildAnalytics('192.168.1.20', 'Mozilla/5.0', 'desktop', 'Edge', 'Windows')
        ));

        // ------------------------------------------------------------
        // Document set 3 - expired
        // ------------------------------------------------------------
        String docId3 = 'DOC-' + randomToken(12);
        String docName3 = 'HIPAA Authorization - ' + pa.Name;
        String publicLink3 = 'http://localhost:3000/docflow/view/' + randomToken(48);

        Datetime created3 = nowGmt.addDays(-7);
        analyticsRows.add(buildWebhookAnalyticsRow(
            analyticsType, pa, recipientId,
            'evt_' + randomToken(18), 'document_sent', created3.addMinutes(5),
            docId3, docName3, 'sent', publicLink3, null, created3, null,
            false, 'sent', null, null,
            null
        ));

        analyticsRows.add(buildWebhookAnalyticsRow(
            analyticsType, pa, recipientId,
            'evt_' + randomToken(18), 'document_expired', created3.addDays(5),
            docId3, docName3, 'expired', publicLink3, null, created3, null,
            false, 'expired', null, null,
            null
        ));

        insert analyticsRows;

        System.debug('Created webhook analytics rows: ' + analyticsRows.size());
    }

    private static SObject buildWebhookAnalyticsRow(
        Schema.SObjectType analyticsType,
        Account pa,
        String recipientId,
        String eventId,
        String eventType,
        Datetime eventTime,
        String documentId,
        String documentName,
        String documentStatus,
        String publicLink,
        String downloadUrl,
        Datetime createdTime,
        Datetime completedTime,
        Boolean includeActor,
        String recipientStatus,
        Datetime signedTime,
        Datetime declinedTime,
        Map<String, Object> analyticsBlock
    ) {
        SObject row = analyticsType.newSObject();
        String docRecipientKey = documentId + '_' + recipientId;

        Map<String, Object> documentBlock = new Map<String, Object>{
            'document_id' => documentId,
            'document_name' => documentName,
            'document_status' => documentStatus,
            'public_link' => publicLink,
            'download_url' => downloadUrl,
            'created_time' => toIso(createdTime),
            'completed_time' => completedTime == null ? null : toIso(completedTime)
        };

        Map<String, Object> actorBlock = includeActor
            ? new Map<String, Object>{
                'recipient_id' => recipientId,
                'name' => pa.Name,
                'email' => pa.PersonEmail,
                'role' => STATIC_ROLE,
                'routing_order' => STATIC_ROUTING_ORDER,
                'status' => recipientStatus,
                'document_recipient_key' => docRecipientKey
            }
            : null;

        List<Object> recipientsSnapshot = new List<Object>{
            new Map<String, Object>{
                'recipient_id' => recipientId,
                'name' => pa.Name,
                'email' => pa.PersonEmail,
                'role' => STATIC_ROLE,
                'routing_order' => STATIC_ROUTING_ORDER,
                'status' => recipientStatus,
                'signed_time' => signedTime == null ? null : toIso(signedTime),
                'declined_time' => declinedTime == null ? null : toIso(declinedTime),
                'document_recipient_key' => docRecipientKey
            }
        };

        Map<String, Object> salesforceContext = new Map<String, Object>{
            'source_record_id' => pa.Id,
            'source_object' => SOURCE_OBJECT,
            'contact_id' => pa.PersonContactId,
            'lead_id' => null,
            'account_id' => pa.Id
        };

        Map<String, Object> rawPayload = new Map<String, Object>{
            'event_id' => eventId,
            'event_type' => eventType,
            'event_time' => toIso(eventTime),
            'source_system' => 'DocFlow',
            'environment' => 'UAT',
            'document' => documentBlock,
            'actor_recipient' => actorBlock,
            'recipients' => recipientsSnapshot,
            'analytics' => analyticsBlock,
            'salesforce_context' => salesforceContext
        };

        putIfExists(row, 'Event_Id__c', eventId);
        putIfExists(row, 'Event_Type__c', eventType);
        putIfExists(row, 'Event_Time__c', eventTime);
        putIfExists(row, 'Source_System__c', 'DocFlow');
        putIfExists(row, 'Environment__c', 'UAT');

        putIfExists(row, 'Document_Id__c', documentId);
        putIfExists(row, 'Document_Name__c', documentName);
        putIfExists(row, 'Document_Status__c', documentStatus);
        putIfExists(row, 'Public_Link__c', publicLink);
        putIfExists(row, 'Download_Url__c', downloadUrl);
        putIfExists(row, 'Document_Created_Time__c', createdTime);
        putIfExists(row, 'Document_Completed_Time__c', completedTime);

        if (includeActor) {
            putIfExists(row, 'Actor_Recipient_Id__c', recipientId);
            putIfExists(row, 'Actor_Name__c', pa.Name);
            putIfExists(row, 'Actor_Email__c', pa.PersonEmail);
            putIfExists(row, 'Actor_Role__c', STATIC_ROLE);
            putIfExists(row, 'Routing_Order__c', STATIC_ROUTING_ORDER);
        }

        putIfExists(row, 'Recipient_Status__c', recipientStatus);
        putIfExists(row, 'Document_Recipient_Key__c', docRecipientKey);

        if (analyticsBlock != null) {
            putIfExists(row, 'IP_Address__c', (String) analyticsBlock.get('ip_address'));
            putIfExists(row, 'User_Agent__c', (String) analyticsBlock.get('user_agent'));
            putIfExists(row, 'Device_Type__c', (String) analyticsBlock.get('device_type'));
            putIfExists(row, 'Browser__c', (String) analyticsBlock.get('browser'));
            putIfExists(row, 'OS__c', (String) analyticsBlock.get('os'));
        }

        putIfExists(row, 'Source_Record_Id__c', (String) pa.Id);
        putIfExists(row, 'Source_Object__c', SOURCE_OBJECT);
        putIfExists(row, 'Account__c', pa.Id);
        putIfExists(row, 'Person_Account__c', pa.Id);
        putIfExists(row, 'Contact__c', pa.PersonContactId);

        putIfExists(row, 'Recipients_Snapshot__c', truncateLongText(JSON.serializePretty(recipientsSnapshot), 131072));
        putIfExists(row, 'Raw_Payload__c', truncateLongText(JSON.serializePretty(rawPayload), 131072));
        putIfExists(row, 'Processing_Status__c', 'Processed');
        putIfExists(row, 'Error_Message__c', null);

        return row;
    }

    private static void createPublicLinkSamplesInternal(Account pa) {
        Schema.SObjectType documentType = Schema.getGlobalDescribe().get(DOCUMENT_OBJECT);
        if (documentType == null) {
            throw new AuraHandledException(DOCUMENT_OBJECT + ' was not found.');
        }

        Schema.SObjectType recipientType = Schema.getGlobalDescribe().get(RECIPIENT_OBJECT);

        List<Map<String, Object>> sampleDocs = new List<Map<String, Object>>{
            new Map<String, Object>{
                'document_name' => 'Non-Disclosure Agreement - ' + pa.Name,
                'merge_fields'  => new Map<String, Object>{
                    'Account.Name' => pa.Name,
                    'Account.Industry' => pa.Industry
                }
            },
            new Map<String, Object>{
                'document_name' => 'Care Coordination Consent - ' + pa.Name,
                'merge_fields'  => new Map<String, Object>{
                    'Account.Name' => pa.Name,
                    'Account.Industry' => pa.Industry
                }
            },
            new Map<String, Object>{
                'document_name' => 'HIPAA Authorization - ' + pa.Name,
                'merge_fields'  => new Map<String, Object>{
                    'Account.Name' => pa.Name,
                    'Account.Industry' => pa.Industry
                }
            }
        };

        List<SObject> parents = new List<SObject>();
        List<String> parentDocumentIds = new List<String>();
        List<String> parentAccessLinks = new List<String>();
        List<String> responseBodies = new List<String>();

        for (Map<String, Object> sampleDoc : sampleDocs) {
            String documentId = randomUuidLike();
            String recipientLinkId = randomUuidLike();
            String accessLink = 'http://localhost:3000/docflow/view/' + randomToken(48);
            Datetime expiresAt = System.now().addDays(30);

            Map<String, Object> requestBody = new Map<String, Object>{
                'template_id' => TEMPLATE_ID,
                'document_name' => (String) sampleDoc.get('document_name'),
                'source_context' => new Map<String, Object>{
                    'record_id' => pa.Id,
                    'object_type' => SOURCE_OBJECT,
                    'salesforce_org_id' => UserInfo.getOrganizationId()
                },
                'recipients' => new List<Object>{
                    new Map<String, Object>{
                        'name' => pa.Name,
                        'email' => pa.PersonEmail,
                        'role' => STATIC_ROLE,
                        'routing_order' => STATIC_ROUTING_ORDER
                    }
                },
                'merge_fields' => sampleDoc.get('merge_fields')
            };

            Map<String, Object> responseBody = new Map<String, Object>{
                'document_id' => documentId,
                'document_name' => (String) sampleDoc.get('document_name'),
                'status' => 'generated',
                'expires_at' => toIso(expiresAt),
                'recipient_links' => new List<Object>{
                    new Map<String, Object>{
                        'id' => recipientLinkId,
                        'name' => pa.Name,
                        'email' => pa.PersonEmail,
                        'role' => STATIC_ROLE,
                        'access_link' => accessLink
                    }
                }
            };

            SObject parent = documentType.newSObject();
            putIfExists(parent, 'Account__c', pa.Id);
            putIfExists(parent, 'Person_Account__c', pa.Id);
            putIfExists(parent, 'Source_Object__c', SOURCE_OBJECT);
            putIfExists(parent, 'Source_Record_Id__c', (String) pa.Id);
            putIfExists(parent, 'Salesforce_Org_Id__c', UserInfo.getOrganizationId());
            putIfExists(parent, 'Template_Id__c', TEMPLATE_ID);
            putIfExists(parent, 'Document_Id__c', documentId);
            putIfExists(parent, 'Document_Name__c', (String) sampleDoc.get('document_name'));
            putIfExists(parent, 'Status__c', 'generated');
            putIfExists(parent, 'Expires_At__c', expiresAt);
            putIfExists(parent, 'Primary_Access_Link__c', accessLink);
            putIfExists(parent, 'Request_Json__c', truncateLongText(JSON.serializePretty(requestBody), 131072));
            putIfExists(parent, 'Response_Json__c', truncateLongText(JSON.serializePretty(responseBody), 131072));
            putIfExists(parent, 'Error_Message__c', null);

            parents.add(parent);
            parentDocumentIds.add(documentId);
            parentAccessLinks.add(accessLink);
            responseBodies.add(JSON.serializePretty(responseBody));
        }

        insert parents;

        if (recipientType != null && hasField(recipientType, 'Doc_Flow_Document__c')) {
            List<SObject> children = new List<SObject>();

            for (Integer i = 0; i < parents.size(); i++) {
                SObject child = recipientType.newSObject();
                putIfExists(child, 'Doc_Flow_Document__c', parents[i].Id);

                Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(responseBodies[i]);
                List<Object> links = (List<Object>) responseBody.get('recipient_links');
                Map<String, Object> link0 = (Map<String, Object>) links[0];

                putIfExists(child, 'Recipient_Link_Id__c', (String) link0.get('id'));
                putIfExists(child, 'Recipient_Name__c', (String) link0.get('name'));
                putIfExists(child, 'Recipient_Email__c', (String) link0.get('email'));
                putIfExists(child, 'Recipient_Role__c', (String) link0.get('role'));
                putIfExists(child, 'Access_Link__c', (String) link0.get('access_link'));

                children.add(child);
            }

            if (!children.isEmpty()) {
                insert children;
            }
        }

        // Update latest NDA shortcut fields on Account if those fields exist.
        Account accUpdate = new Account(Id = pa.Id);
        Boolean shouldUpdate = false;
        shouldUpdate = putIfExists(accUpdate, 'Non_Disclosure_Doc_Link__c', parentAccessLinks[0]) || shouldUpdate;
        shouldUpdate = putIfExists(accUpdate, 'Non_Disclosure_Doc_Id__c', parentDocumentIds[0]) || shouldUpdate;
        shouldUpdate = putIfExists(accUpdate, 'Non_Disclosure_Doc_Status__c', 'generated') || shouldUpdate;
        shouldUpdate = putIfExists(accUpdate, 'Non_Disclosure_Doc_Expires_At__c', System.now().addDays(30)) || shouldUpdate;

        if (shouldUpdate) {
            update accUpdate;
        }

        System.debug('Created Doc Flow document rows: ' + parents.size());
    }

    private static Map<String, Object> buildAnalytics(
        String ipAddress,
        String userAgent,
        String deviceType,
        String browser,
        String os
    ) {
        return new Map<String, Object>{
            'ip_address' => ipAddress,
            'user_agent' => userAgent,
            'device_type' => deviceType,
            'browser' => browser,
            'os' => os
        };
    }

    private static Boolean putIfExists(SObject row, String fieldApiName, Object value) {
        if (row == null || String.isBlank(fieldApiName) || value == null) {
            return false;
        }

        Map<String, Schema.SObjectField> fieldsMap = row.getSObjectType().getDescribe().fields.getMap();
        if (!fieldsMap.containsKey(fieldApiName)) {
            return false;
        }

        row.put(fieldApiName, value);
        return true;
    }

    private static Boolean hasField(Schema.SObjectType sobType, String fieldApiName) {
        if (sobType == null || String.isBlank(fieldApiName)) {
            return false;
        }
        return sobType.getDescribe().fields.getMap().containsKey(fieldApiName);
    }

    private static String toIso(Datetime dt) {
        if (dt == null) {
            return null;
        }
        return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    private static String truncateLongText(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }

    private static String randomToken(Integer length) {
        String seed = String.valueOf(System.now().getTime()) + '_' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String hex = EncodingUtil.convertToHex(Crypto.generateDigest('SHA1', Blob.valueOf(seed)));
        Integer safeLength = Math.min(length, hex.length());
        return hex.substring(0, safeLength);
    }

    private static String randomUuidLike() {
        String hex = randomToken(32).toLowerCase();
        return hex.substring(0, 8) + '-' +
               hex.substring(8, 12) + '-' +
               hex.substring(12, 16) + '-' +
               hex.substring(16, 20) + '-' +
               hex.substring(20, 32);
    }
}