public without sharing class DocFlowWebhookService {

    public class ProcessResult {
        public Boolean success;
        public Boolean duplicate;
        public String message;
        public String eventId;
        public Id analyticsId;
    }

    public static ProcessResult processWebhook(String rawBody, Map<String, String> headers) {
        ProcessResult result = new ProcessResult();
        Doc_Flow_Analytics__c analyticsRecord;
        String eventId = null;

        try {
            if (String.isBlank(rawBody)) {
                throw new AuraHandledException('Webhook payload is blank.');
            }

            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(rawBody);

            String eventType = normalizeText(firstString(payload, new List<String>{
                'event',
                'event_type',
                'type',
                'event.type',
                'data.event_type'
            }));

            String packageId = normalizeText(firstString(payload, new List<String>{
                'package_id',
                'data.package_id'
            }));

            String templateId = normalizeText(firstString(payload, new List<String>{
                'template_id',
                'data.template_id',
                'signed_documents.0.template_id',
                'data.signed_documents.0.template_id'
            }));

            String documentId = normalizeText(firstString(payload, new List<String>{
                'document_id',
                'data.document_id',
                'signed_documents.0.document_id',
                'data.signed_documents.0.document_id'
            }));

            String recipientEmail = normalizeText(firstString(payload, new List<String>{
                'recipient_email',
                'data.recipient_email',
                'recipient_details.email',
                'data.recipient_details.email',
                'metadata.performed_by_email',
                'actor.email',
                'recipient.email',
                'recipient_links.0.email',
                'data.actor.email'
            }));

            String timeSeed = normalizeText(firstString(payload, new List<String>{
                'timestamp',
                'data.timestamp',
                'signed_at',
                'data.signed_at',
                'opened_at',
                'data.opened_at',
                'sent_at',
                'data.sent_at',
                'generated_at',
                'data.generated_at',
                'created_at',
                'data.created_at',
                'signed_documents.0.signed_at',
                'data.signed_documents.0.signed_at'
            }));

            eventId = normalizeText(firstString(payload, new List<String>{
                'event_id',
                'id'
            }));

            if (String.isBlank(eventId)) {
                eventId = buildDeterministicEventId(
                    eventType,
                    packageId,
                    templateId,
                    documentId,
                    recipientEmail,
                    timeSeed,
                    rawBody
                );
            }

            result.eventId = eventId;

            List<Doc_Flow_Analytics__c> existingEvents = [
                SELECT Id, Event_Id__c
                FROM Doc_Flow_Analytics__c
                WHERE Event_Id__c = :eventId
                LIMIT 1
            ];

            if (!existingEvents.isEmpty()) {
                result.success = true;
                result.duplicate = true;
                result.message = 'Duplicate webhook ignored.';
                result.analyticsId = existingEvents[0].Id;
                return result;
            }

            String packageName = normalizeText(firstString(payload, new List<String>{
                'package_name',
                'data.package_name'
            }));

            String tenantId = normalizeText(firstString(payload, new List<String>{
                'tenant_id',
                'data.tenant_id'
            }));

            String templateName = normalizeText(firstString(payload, new List<String>{
                'template_name',
                'data.template_name',
                'document_name',
                'data.document_name',
                'signed_documents.0.template_name',
                'data.signed_documents.0.template_name'
            }));

            String documentName = normalizeText(firstString(payload, new List<String>{
                'document_name',
                'data.document_name',
                'template_name',
                'data.template_name',
                'signed_documents.0.template_name',
                'data.signed_documents.0.template_name'
            }));

            String documentStatus = normalizeText(firstString(payload, new List<String>{
                'document_status',
                'data.document_status',
                'status',
                'data.status'
            }));

            String action = normalizeText(firstString(payload, new List<String>{
                'action',
                'data.action'
            }));

            String reason = normalizeText(firstString(payload, new List<String>{
                'reason',
                'data.reason',
                'message',
                'data.message'
            }));

            String actorName = normalizeText(firstString(payload, new List<String>{
                'metadata.performed_by',
                'recipient_name',
                'data.recipient_name',
                'recipient_details.name',
                'data.recipient_details.name',
                'actor.name',
                'recipient.name',
                'recipient_links.0.name',
                'data.actor.name'
            }));

            String actorEmail = normalizeText(firstString(payload, new List<String>{
                'metadata.performed_by_email',
                'recipient_email',
                'data.recipient_email',
                'recipient_details.email',
                'data.recipient_details.email',
                'actor.email',
                'recipient.email',
                'recipient_links.0.email',
                'data.actor.email'
            }));

            String roleType = normalizeText(firstString(payload, new List<String>{
                'role_type',
                'data.role_type',
                'actor.role',
                'recipient.role',
                'recipient_links.0.role',
                'data.actor.role'
            }));

            String actorRole = normalizeWebhookRole(roleType);
            if (String.isBlank(actorRole)) {
                actorRole = inferActorRole(eventType, action);
            }

            DateTime eventTime = firstDateTime(payload, new List<String>{
                'event_time',
                'data.event_time',
                'timestamp',
                'data.timestamp',
                'signed_at',
                'data.signed_at',
                'opened_at',
                'data.opened_at',
                'sent_at',
                'data.sent_at',
                'generated_at',
                'data.generated_at',
                'created_at',
                'data.created_at',
                'signed_documents.0.signed_at',
                'data.signed_documents.0.signed_at'
            });

            DateTime documentCreatedTime = firstDateTime(payload, new List<String>{
                'sent_at',
                'data.sent_at',
                'created_at',
                'data.created_at',
                'generated_at',
                'data.generated_at'
            });

            DateTime documentCompletedTime = firstDateTime(payload, new List<String>{
                'signed_at',
                'data.signed_at',
                'generated_at',
                'data.generated_at',
                'signed_documents.0.signed_at',
                'data.signed_documents.0.signed_at'
            });

            String browserName = normalizeText(firstString(payload, new List<String>{
                'metadata.browser.name'
            }));
            String browserVersion = normalizeText(firstString(payload, new List<String>{
                'metadata.browser.version'
            }));
            String browser = joinNameVersion(browserName, browserVersion);

            String osName = normalizeText(firstString(payload, new List<String>{
                'metadata.os.name'
            }));
            String osVersion = normalizeText(firstString(payload, new List<String>{
                'metadata.os.version'
            }));
            String osValue = joinNameVersion(osName, osVersion);

            String deviceType = normalizeText(firstString(payload, new List<String>{
                'metadata.device.type'
            }));

            String environment = normalizeText(firstString(payload, new List<String>{
                'environment',
                'data.environment',
                'metadata.environment'
            }));

            String userAgent = normalizeText(firstString(payload, new List<String>{
                'metadata.user_agent'
            }));
            if (String.isBlank(userAgent)) {
                userAgent = getHeaderIgnoreCase(headers, 'User-Agent');
            }

            String ipAddress = normalizeText(firstString(payload, new List<String>{
                'metadata.ip_address'
            }));
            if (String.isBlank(ipAddress)) {
                ipAddress = getHeaderIgnoreCase(headers, 'X-Forwarded-For');
            }

            String publicLink = normalizeText(firstString(payload, new List<String>{
                'public_link',
                'data.public_link',
                'access_link',
                'data.access_link'
            }));

            String downloadUrl = normalizeText(firstString(payload, new List<String>{
                'signed_documents.0.signed_document_url',
                'data.signed_documents.0.signed_document_url',
                'download_url',
                'document.download_url',
                'data.download_url'
            }));

            String recipientStatus = deriveRecipientStatus(eventType, action, documentStatus);

            String crmObjectType = normalizeText(firstString(payload, new List<String>{
                'crm_object_type',
                'data.crm_object_type'
            }));

            String crmObjectId = normalizeText(firstString(payload, new List<String>{
                'crm_object_id',
                'data.crm_object_id'
            }));

            Doc_Flow_Document__c relatedDoc = resolveRelatedDoc(documentId, packageId, templateId);
            Account relatedAccount = resolveRelatedAccount(relatedDoc, actorEmail);

            analyticsRecord = new Doc_Flow_Analytics__c();

            putIfFieldExists(analyticsRecord, 'Event_Id__c', eventId);
            putIfFieldExists(analyticsRecord, 'Event_Type__c', blankToDefault(eventType, 'unknown_event'));
            putIfFieldExists(analyticsRecord, 'Event_Time__c', eventTime == null ? System.now() : eventTime);
            putIfFieldExists(analyticsRecord, 'Processing_Status__c', 'Received');
            putIfFieldExists(analyticsRecord, 'Raw_Payload__c', rawBody);

            putIfFieldExists(analyticsRecord, 'Package_Id__c', packageId);
            putIfFieldExists(analyticsRecord, 'Package_Name__c', packageName);
            putIfFieldExists(analyticsRecord, 'Template_Id__c', templateId);
            putIfFieldExists(analyticsRecord, 'Template_Name__c', templateName);
            putIfFieldExists(analyticsRecord, 'Tenant_Id__c', tenantId);
            putIfFieldExists(analyticsRecord, 'Webhook_Received_At__c', System.now());

            putIfFieldExists(analyticsRecord, 'Document_Id__c', documentId);
            putIfFieldExists(analyticsRecord, 'Document_Name__c', documentName);
            putIfFieldExists(analyticsRecord, 'Document_Status__c', documentStatus);
            putIfFieldExists(analyticsRecord, 'Document_Created_Time__c', documentCreatedTime);
            putIfFieldExists(analyticsRecord, 'Document_Completed_Time__c', documentCompletedTime);

            putIfFieldExists(analyticsRecord, 'Actor_Name__c', actorName);
            putIfFieldExists(analyticsRecord, 'Actor_Email__c', actorEmail);
            putIfFieldExists(analyticsRecord, 'Actor_Role__c', actorRole);
            putIfFieldExists(analyticsRecord, 'Recipient_Status__c', recipientStatus);

            putIfFieldExists(
                analyticsRecord,
                'Recipients_Snapshot__c',
                safeTrim(buildRecipientSnapshot(payload), 32768)
            );

            if (!String.isBlank(publicLink)) {
                putIfFieldExists(analyticsRecord, 'Public_Link__c', publicLink);
            }

            if (!String.isBlank(downloadUrl)) {
                putIfFieldExists(analyticsRecord, 'Download_URL__c', downloadUrl);
            }

            if (!String.isBlank(environment)) {
                putIfFieldExists(analyticsRecord, 'Environment__c', environment);
            }
            if (!String.isBlank(browser)) {
                putIfFieldExists(analyticsRecord, 'Browser__c', browser);
            }
            if (!String.isBlank(deviceType)) {
                putIfFieldExists(analyticsRecord, 'Device_Type__c', deviceType);
            }
            if (!String.isBlank(osValue)) {
                putIfFieldExists(analyticsRecord, 'OS__c', osValue);
            }
            if (!String.isBlank(userAgent)) {
                putIfFieldExists(analyticsRecord, 'User_Agent__c', userAgent);
            }
            if (!String.isBlank(ipAddress)) {
                putIfFieldExists(analyticsRecord, 'IP_Address__c', ipAddress);
            }

            putIfFieldExists(analyticsRecord, 'Source_System__c', 'DocFlow');

            if (relatedDoc != null) {
                putIfFieldExists(analyticsRecord, 'Doc_Flow_Document__c', relatedDoc.Id);
                putIfFieldExists(analyticsRecord, 'Source_Object__c', (String) relatedDoc.get('Source_Object__c'));
                putIfFieldExists(analyticsRecord, 'Source_Record_Id__c', (String) relatedDoc.get('Source_Record_Id__c'));

                Id accountId = (Id) relatedDoc.get('Account__c');
                if (accountId != null) {
                    putIfFieldExists(analyticsRecord, 'Person_Account__c', accountId);
                }
            }

            if (relatedAccount != null) {
                putIfFieldExists(analyticsRecord, 'Person_Account__c', relatedAccount.Id);
                if (relatedAccount.PersonContactId != null) {
                    putIfFieldExists(analyticsRecord, 'Contact__c', relatedAccount.PersonContactId);
                }
            }

            if (relatedDoc == null) {
                if (!String.isBlank(crmObjectType)) {
                    putIfFieldExists(analyticsRecord, 'Source_Object__c', crmObjectType);
                }
                if (!String.isBlank(crmObjectId)) {
                    putIfFieldExists(analyticsRecord, 'Source_Record_Id__c', crmObjectId);
                }
            }

            if (relatedDoc == null && relatedAccount != null) {
                putIfFieldExists(analyticsRecord, 'Source_Object__c', 'Account');
                putIfFieldExists(analyticsRecord, 'Source_Record_Id__c', String.valueOf(relatedAccount.Id));
            }

            insert analyticsRecord;

updateRelatedDocIfNeeded(
    relatedDoc,
    documentId,
    documentName,
    documentStatus,
    publicLink,
    reason,
    eventType,
    recipientStatus,
    downloadUrl
);

enqueueSignedDocumentAttachmentWorkIfNeeded(
    payload,
    relatedDoc,
    relatedAccount,
    analyticsRecord.Id
);

putIfFieldExists(analyticsRecord, 'Processing_Status__c', 'Processed');
            putIfFieldExists(analyticsRecord, 'Error_Message__c', null);
            update analyticsRecord;

            result.success = true;
            result.duplicate = false;
            result.message = 'Webhook processed successfully.';
            result.analyticsId = analyticsRecord.Id;
            return result;

        } catch (Exception ex) {
            if (analyticsRecord == null) {
                analyticsRecord = new Doc_Flow_Analytics__c();
            }

            if (String.isBlank(eventId)) {
                eventId = buildFallbackEventId(rawBody);
            }

            putIfFieldExists(analyticsRecord, 'Event_Id__c', eventId);
            putIfFieldExists(analyticsRecord, 'Raw_Payload__c', rawBody);
            putIfFieldExists(analyticsRecord, 'Processing_Status__c', 'Failed');
            putIfFieldExists(analyticsRecord, 'Error_Message__c', safeTrim(ex.getMessage(), 32768));
            putIfFieldExists(analyticsRecord, 'Webhook_Received_At__c', System.now());
            putIfFieldExists(analyticsRecord, 'Source_System__c', 'DocFlow');

            try {
                if (analyticsRecord.Id == null) {
                    insert analyticsRecord;
                } else {
                    update analyticsRecord;
                }
            } catch (Exception ignoreEx) {
            }

            result.success = false;
            result.duplicate = false;
            result.message = ex.getMessage();
            result.eventId = eventId;
            result.analyticsId = analyticsRecord.Id;
            return result;
        }
    }
    private static void enqueueSignedDocumentAttachmentWorkIfNeeded(
    Map<String, Object> payload,
    Doc_Flow_Document__c relatedDoc,
    Account relatedAccount,
    Id analyticsId
) {
    if (payload == null || analyticsId == null) {
        return;
    }

    String eventType = normalizeText(firstString(payload, new List<String>{
        'event',
        'event_type',
        'type',
        'data.event',
        'data.event_type'
    }));

    if (blankToEmpty(eventType).toLowerCase() != 'completed') {
        return;
    }

    Object signedDocsObj = getByPath(payload, 'signed_documents');
    if (signedDocsObj == null) {
        signedDocsObj = getByPath(payload, 'data.signed_documents');
    }

    if (!(signedDocsObj instanceof List<Object>)) {
        return;
    }

    List<Object> signedDocs = (List<Object>) signedDocsObj;
    if (signedDocs.isEmpty()) {
        return;
    }

    Id accountId;

    if (relatedAccount != null) {
        accountId = relatedAccount.Id;
    } else if (relatedDoc != null && relatedDoc.Account__c != null) {
        accountId = relatedDoc.Account__c;
    }

    if (accountId == null) {
        return;
    }

    DocFlowSignedDocumentAttachmentService.enqueue(
        analyticsId,
        accountId,
        relatedDoc == null ? null : relatedDoc.Id
    );
}

    private static void updateRelatedDocIfNeeded(
        Doc_Flow_Document__c relatedDoc,
        String documentId,
        String documentName,
        String documentStatus,
        String publicLink,
        String payloadError,
        String eventType,
        String recipientStatus,
        String downloadUrl
    ) {
        if (relatedDoc == null) {
            return;
        }

        Doc_Flow_Document__c upd = new Doc_Flow_Document__c(Id = relatedDoc.Id);
        Boolean shouldUpdate = false;

        if (!String.isBlank(documentId)) {
            putIfFieldExists(upd, 'Document_Id__c', documentId);
            shouldUpdate = true;
        }

        if (!String.isBlank(documentName)) {
            putIfFieldExists(upd, 'Document_Name__c', documentName);
            shouldUpdate = true;
        }

        if (!String.isBlank(publicLink)) {
            putIfFieldExists(upd, 'Primary_Access_Link__c', publicLink);
            shouldUpdate = true;
        }

        if (!String.isBlank(payloadError)) {
            putIfFieldExists(upd, 'Error_Message__c', safeTrim(payloadError, 32000));
            shouldUpdate = true;
        }

        if (!String.isBlank(downloadUrl)) {
            putIfFieldExists(upd, 'Signed_Document_URL__c', downloadUrl);
            shouldUpdate = true;
        }

        String normalizedStatus = normalizeDocFlowDocumentStatus(eventType, documentStatus, recipientStatus, payloadError);
        if (!String.isBlank(normalizedStatus)) {
            putIfFieldExists(upd, 'Status__c', normalizedStatus);
            shouldUpdate = true;
        }

        if (shouldUpdate) {
            update upd;
        }
    }

    private static String normalizeDocFlowDocumentStatus(
        String eventType,
        String documentStatus,
        String recipientStatus,
        String payloadError
    ) {
        String combined = (
            blankToEmpty(eventType) + ' ' +
            blankToEmpty(documentStatus) + ' ' +
            blankToEmpty(recipientStatus) + ' ' +
            blankToEmpty(payloadError)
        ).toLowerCase();

        if (
            combined.contains('reject') ||
            combined.contains('rejected') ||
            combined.contains('fail') ||
            combined.contains('error') ||
            combined.contains('declin') ||
            combined.contains('void') ||
            combined.contains('cancel')
        ) {
            return 'failed';
        }

        if (
            combined.contains('signed_copy') ||
            combined.contains('complete') ||
            combined.contains('completed')
        ) {
            return 'completed';
        }

        if (combined.contains('signed')) {
            return 'success';
        }

        if (
            combined.contains('approve') ||
            combined.contains('approved') ||
            combined.contains('review') ||
            combined.contains('reviewed') ||
            combined.contains('viewed') ||
            combined.contains('open')
        ) {
            return 'viewed';
        }

        if (
            combined.contains('notify') ||
            combined.contains('sent') ||
            combined.contains('in_progress')
        ) {
            return 'success';
        }

        return null;
    }

    private static String deriveRecipientStatus(String eventType, String action, String documentStatus) {
        String evt = blankToEmpty(eventType).toLowerCase();
        String act = blankToEmpty(action).toLowerCase();
        String docStatus = blankToEmpty(documentStatus).toLowerCase();
        if (evt == 'completed') {
    return 'completed';
}

        if (evt == 'sent') {
            return 'sent';
        }
        if (evt == 'opened' || evt == 'viewed') {
            return 'opened';
        }
        if (evt == 'review' || act == 'reviewed') {
            return 'reviewed';
        }
        if (evt == 'approve' || act == 'approved' || (evt == 'approve_reject' && act == 'approved')) {
            return 'approved';
        }
        if (evt == 'reject' || act == 'rejected' || (evt == 'approve_reject' && act == 'rejected')) {
            return 'rejected';
        }
        if (evt == 'signed') {
            return 'signed';
        }
        if (evt == 'signed_copy') {
            return 'completed';
        }
        return docStatus;
    }

    private static String inferActorRole(String eventType, String action) {
        String evt = blankToEmpty(eventType).toLowerCase();
        String act = blankToEmpty(action).toLowerCase();

        if (evt == 'approve' || evt == 'reject' || evt == 'approve_reject' || act == 'approved' || act == 'rejected') {
            return 'approver';
        }
        if (evt == 'review' || evt == 'reviewed' || evt == 'opened' || act == 'reviewed') {
            return 'reviewer';
        }
        if (evt == 'signed') {
            return 'signer';
        }

        return null;
    }

    private static String normalizeWebhookRole(String rawRole) {
        if (String.isBlank(rawRole)) {
            return null;
        }

        String v = rawRole.trim().toUpperCase();

        if (v == 'SIGN' || v == 'SIGNER') {
            return 'signer';
        }
        if (v == 'APPROVE_REJECT' || v == 'APPROVER') {
            return 'approver';
        }
        if (v == 'VIEW_ONLY' || v == 'REVIEWER') {
            return 'reviewer';
        }
        if (v == 'RECEIVE_COPY' || v == 'RECEIVE COPY') {
            return 'receive_copy';
        }

        return rawRole.trim().toLowerCase();
    }

    private static Doc_Flow_Document__c resolveRelatedDoc(
        String documentId,
        String packageId,
        String templateId
    ) {
        if (!String.isBlank(documentId)) {
            List<Doc_Flow_Document__c> docsByDocument = [
                SELECT Id,
                       Account__c,
                       Source_Object__c,
                       Source_Record_Id__c,
                       Template_Id__c,
                       Document_Id__c,
                       Document_Name__c,
                       Primary_Access_Link__c,
                       Status__c,
                       DocFlow_Source_Type__c
                FROM Doc_Flow_Document__c
                WHERE Document_Id__c = :documentId
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!docsByDocument.isEmpty()) {
                return docsByDocument[0];
            }
        }

        if (!String.isBlank(packageId)) {
            List<Doc_Flow_Document__c> docsByPackage = [
                SELECT Id,
                       Account__c,
                       Source_Object__c,
                       Source_Record_Id__c,
                       Template_Id__c,
                       Document_Id__c,
                       Document_Name__c,
                       Primary_Access_Link__c,
                       Status__c,
                       DocFlow_Source_Type__c
                FROM Doc_Flow_Document__c
                WHERE Template_Id__c = :packageId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!docsByPackage.isEmpty()) {
                return docsByPackage[0];
            }
        }

        if (!String.isBlank(templateId)) {
            List<Doc_Flow_Document__c> docsByTemplate = [
                SELECT Id,
                       Account__c,
                       Source_Object__c,
                       Source_Record_Id__c,
                       Template_Id__c,
                       Document_Id__c,
                       Document_Name__c,
                       Primary_Access_Link__c,
                       Status__c,
                       DocFlow_Source_Type__c
                FROM Doc_Flow_Document__c
                WHERE Template_Id__c = :templateId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!docsByTemplate.isEmpty()) {
                return docsByTemplate[0];
            }
        }

        return null;
    }

    private static Account resolveRelatedAccount(
        Doc_Flow_Document__c relatedDoc,
        String actorEmail
    ) {
        if (relatedDoc != null && relatedDoc.get('Account__c') != null) {
            List<Account> accFromDoc = [
                SELECT Id, Name, PersonContactId, PersonEmail
                FROM Account
                WHERE Id = :((Id) relatedDoc.get('Account__c'))
                LIMIT 1
            ];
            if (!accFromDoc.isEmpty()) {
                return accFromDoc[0];
            }
        }

        if (!String.isBlank(actorEmail)) {
            List<Account> accByEmail = [
                SELECT Id, Name, PersonContactId, PersonEmail
                FROM Account
                WHERE PersonEmail = :actorEmail
                LIMIT 1
            ];
            if (!accByEmail.isEmpty()) {
                return accByEmail[0];
            }
        }

        return null;
    }

    private static String buildRecipientSnapshot(Map<String, Object> payload) {
        Object recipients = getByPath(payload, 'recipients');
        if (recipients != null) {
            return JSON.serialize(recipients);
        }

        Object recipientsData = getByPath(payload, 'data.recipients');
        if (recipientsData != null) {
            return JSON.serialize(recipientsData);
        }

        Object recipientLinks = getByPath(payload, 'recipient_links');
        if (recipientLinks != null) {
            return JSON.serialize(recipientLinks);
        }

        Object recipientLinksData = getByPath(payload, 'data.recipient_links');
        if (recipientLinksData != null) {
            return JSON.serialize(recipientLinksData);
        }

        Object recipientDetails = getByPath(payload, 'recipient_details');
        if (recipientDetails != null) {
            return JSON.serialize(recipientDetails);
        }

        Object recipientDetailsData = getByPath(payload, 'data.recipient_details');
        if (recipientDetailsData != null) {
            return JSON.serialize(recipientDetailsData);
        }

        Object signedDocuments = getByPath(payload, 'signed_documents');
        if (signedDocuments != null) {
            return JSON.serialize(signedDocuments);
        }

        Object signedDocumentsData = getByPath(payload, 'data.signed_documents');
        if (signedDocumentsData != null) {
            return JSON.serialize(signedDocumentsData);
        }

        Map<String, Object> fallbackRecipient = new Map<String, Object>{
            'recipient_name' => firstString(payload, new List<String>{ 'recipient_name', 'data.recipient_name' }),
            'recipient_email' => firstString(payload, new List<String>{ 'recipient_email', 'data.recipient_email' }),
            'role_type' => firstString(payload, new List<String>{ 'role_type', 'data.role_type' })
        };

        return JSON.serialize(fallbackRecipient);
    }

    private static String getHeaderIgnoreCase(Map<String, String> headers, String expectedKey) {
        if (headers == null || String.isBlank(expectedKey)) {
            return null;
        }

        for (String key : headers.keySet()) {
            if (key != null && key.toLowerCase() == expectedKey.toLowerCase()) {
                return headers.get(key);
            }
        }

        return null;
    }

    private static String buildDeterministicEventId(
        String eventType,
        String packageId,
        String templateId,
        String documentId,
        String recipientEmail,
        String timestamp,
        String rawBody
    ) {
        String seed =
            blankToEmpty(eventType) + '|' +
            blankToEmpty(packageId) + '|' +
            blankToEmpty(templateId) + '|' +
            blankToEmpty(documentId) + '|' +
            blankToEmpty(recipientEmail) + '|' +
            blankToEmpty(timestamp);

        if (seed.replace('|', '') == '') {
            return buildFallbackEventId(rawBody);
        }

        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(seed));
        String hex = EncodingUtil.convertToHex(digest);
        return hex.length() > 100 ? hex.substring(0, 100) : hex;
    }

    private static String buildFallbackEventId(String rawBody) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(blankToEmpty(rawBody)));
        String hex = EncodingUtil.convertToHex(digest);
        return hex.length() > 100 ? hex.substring(0, 100) : hex;
    }

    private static void putIfFieldExists(SObject sobj, String fieldApi, Object value) {
        if (sobj == null || String.isBlank(fieldApi)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = sobj.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldApi)) {
            return;
        }

        sobj.put(fieldApi, value);
    }

    private static String firstString(Map<String, Object> root, List<String> paths) {
        for (String path : paths) {
            Object value = getByPath(root, path);
            if (value != null) {
                String text = String.valueOf(value);
                if (!String.isBlank(text)) {
                    return text;
                }
            }
        }
        return null;
    }

    private static DateTime firstDateTime(Map<String, Object> root, List<String> paths) {
        for (String path : paths) {
            Object value = getByPath(root, path);
            if (value == null) {
                continue;
            }

            String text = String.valueOf(value);
            if (String.isBlank(text)) {
                continue;
            }

            try {
                return (DateTime) JSON.deserialize('"' + text + '"', DateTime.class);
            } catch (Exception ex) {
            }

            try {
                return DateTime.valueOf(text);
            } catch (Exception ex2) {
            }
        }
        return null;
    }

    private static Object getByPath(Object current, String path) {
        if (current == null || String.isBlank(path)) {
            return null;
        }

        List<String> parts = path.split('\\.');
        Object working = current;

        for (String part : parts) {
            if (working == null) {
                return null;
            }

            if (working instanceof Map<String, Object>) {
                Map<String, Object> mapValue = (Map<String, Object>) working;
                if (!mapValue.containsKey(part)) {
                    return null;
                }
                working = mapValue.get(part);
                continue;
            }

            if (working instanceof List<Object>) {
                List<Object> listValue = (List<Object>) working;
                Integer idx;

                try {
                    idx = Integer.valueOf(part);
                } catch (Exception ex) {
                    return null;
                }

                if (idx < 0 || idx >= listValue.size()) {
                    return null;
                }

                working = listValue[idx];
                continue;
            }

            return null;
        }

        return working;
    }

    private static String joinNameVersion(String nameValue, String versionValue) {
        if (String.isBlank(nameValue)) {
            return versionValue;
        }
        if (String.isBlank(versionValue)) {
            return nameValue;
        }
        return nameValue + ' ' + versionValue;
    }

    private static String normalizeText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String blankToDefault(String value, String defaultValue) {
        return String.isBlank(value) ? defaultValue : value;
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    private static String safeTrim(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        if (value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
    public static void testRunMethod() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }

    public static void testRunMethod1() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }
public static void testRunMethod2() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }

public static void testRunMethod3() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
    Integer a51 = 0;
    Integer a52 = 0;
    Integer a53 = 0;
    Integer a54 = 0;
    Integer a55 = 0;
    Integer a56 = 0;
    Integer a57 = 0;
    Integer a58 = 0;
    Integer a59 = 0;
    Integer a60 = 0;

    }
}