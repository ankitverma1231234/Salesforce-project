public without sharing class DocFlowAnalyticsProcessor {

    private static Boolean isRunning = false;

    private static final String TEMPLATE_SEND_DEV_NAME      = 'Docflow_Send_Template';
    private static final String TEMPLATE_APPROVAL_DEV_NAME  = 'Docflow_Approval_Email';
    private static final String TEMPLATE_REVIEW_DEV_NAME    = 'Docflow_Review_Email';
    private static final String TEMPLATE_COMPLETED_DEV_NAME = 'Completed_Docflow_Template';

    public static void handleAfter(
        List<Doc_Flow_Analytics__c> newList,
        Map<Id, Doc_Flow_Analytics__c> oldMap
    ) {
        if (isRunning) {
            return;
        }

        isRunning = true;
        try {
            List<AnalyticsEventContext> contexts = new List<AnalyticsEventContext>();

            for (Doc_Flow_Analytics__c rec : newList) {
                if (!shouldProcess(rec, oldMap)) {
                    continue;
                }

                AnalyticsEventContext ctx = buildContext(rec);
                if (ctx == null) {
                    continue;
                }

                contexts.add(ctx);
            }

            if (contexts.isEmpty()) {
                return;
            }

            processContexts(contexts);

        } finally {
            isRunning = false;
        }
    }

    private static Boolean shouldProcess(
        Doc_Flow_Analytics__c rec,
        Map<Id, Doc_Flow_Analytics__c> oldMap
    ) {
        if (rec == null) {
            return false;
        }

        String newStatus = safeString(rec.get('Processing_Status__c'));
        if (newStatus != 'Processed') {
            return false;
        }

        if (oldMap == null || !oldMap.containsKey(rec.Id)) {
            return true;
        }

        Doc_Flow_Analytics__c oldRec = oldMap.get(rec.Id);
        String oldStatus = oldRec == null ? null : safeString(oldRec.get('Processing_Status__c'));
        return oldStatus != 'Processed';
    }

    private static AnalyticsEventContext buildContext(Doc_Flow_Analytics__c rec) {
        String rawPayload = safeString(rec.get('Raw_Payload__c'));
        if (String.isBlank(rawPayload)) {
            return null;
        }
    
        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(rawPayload);
        } catch (Exception ex) {
            return null;
        }
    
        AnalyticsEventContext ctx = new AnalyticsEventContext();
        ctx.analyticsId = rec.Id;
        ctx.rawPayload = payload;
        ctx.eventType = normalizeText(firstString(payload, new List<String>{
            'event',
            'event_type',
            'type'
        }));
        ctx.action = normalizeText(firstString(payload, new List<String>{
            'action'
        }));
        ctx.packageId = normalizeText(firstString(payload, new List<String>{
            'package_id'
        }));
        ctx.documentId = normalizeText(firstString(payload, new List<String>{
            'document_id',
            'signed_documents.0.document_id'
        }));
        ctx.actorEmail = normalizeText(firstNonBlank(
            safeString(rec.get('Actor_Email__c')),
            firstString(payload, new List<String>{
                'recipient_email',
                'recipient_details.email',
                'metadata.performed_by_email'
            })
        ));
        ctx.actorName = normalizeText(firstNonBlank(
            safeString(rec.get('Actor_Name__c')),
            firstString(payload, new List<String>{
                'recipient_name',
                'recipient_details.name',
                'metadata.performed_by'
            })
        ));
        ctx.actorRole = normalizeText(firstNonBlank(
            safeString(rec.get('Actor_Role__c')),
            inferRoleFromPayload(ctx.eventType, ctx.action)
        ));
        ctx.personAccountId = (Id) rec.get('Person_Account__c');
        ctx.sourceRecordId = safeString(rec.get('Source_Record_Id__c'));
        ctx.downloadUrl = normalizeText(firstString(payload, new List<String>{
            'signed_documents.0.signed_document_url',
            'download_url'
        }));
        ctx.docFlowDocumentId = (Id) rec.get('Doc_Flow_Document__c');
    
        return ctx;
    }

    private static void processContexts(List<AnalyticsEventContext> contexts) {
        System.debug(LoggingLevel.ERROR, 'DocFlowAnalyticsProcessor|processContexts|START|contexts=' + (contexts == null ? 0 : contexts.size()));
    
        Map<String, PendingEmailWork> pendingEmailByKey = new Map<String, PendingEmailWork>();
        Map<Id, Doc_Flow_Document__c> docUpdatesById = new Map<Id, Doc_Flow_Document__c>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> docIds = new Set<Id>();
        List<DocFlowSmsService.SmsWork> smsWorkToSend = new List<DocFlowSmsService.SmsWork>();
        Set<Id> docIdsToCancelReminders = new Set<Id>();
        List<ReminderActivationWork> reminderActivationWork = new List<ReminderActivationWork>();
    
        for (AnalyticsEventContext ctx : contexts) {
            if (ctx != null && ctx.docFlowDocumentId != null) {
                docIds.add(ctx.docFlowDocumentId);
            }
        }
    
        Map<Id, Doc_Flow_Document__c> docMap = new Map<Id, Doc_Flow_Document__c>();
        if (!docIds.isEmpty()) {
            docMap = new Map<Id, Doc_Flow_Document__c>([
                SELECT Id,
                       Account__c,
                       Template_Id__c,
                       Source_Record_Id__c,
                       Recipient_Config_Json__c,
                       Response_Json__c,
                       Status__c,
                       Primary_Access_Link__c,
                       Error_Message__c,
                       DocFlow_Source_Type__c
                FROM Doc_Flow_Document__c
                WHERE Id IN :docIds
            ]);
        }
    
        for (AnalyticsEventContext ctx : contexts) {
            Doc_Flow_Document__c doc = (ctx.docFlowDocumentId == null) ? null : docMap.get(ctx.docFlowDocumentId);
            if (doc == null) {
                continue;
            }
    
            if (doc.Account__c != null) {
                accountIds.add(doc.Account__c);
            }
    
            Map<String, Object> config;
            Map<String, Object> responseJson;
    
            try {
                config = (Map<String, Object>) JSON.deserializeUntyped(doc.Recipient_Config_Json__c);
            } catch (Exception ex) {
                addDocError(docUpdatesById, doc.Id, 'Cadence skipped: Recipient_Config_Json__c is invalid.');
                continue;
            }
    
            try {
                responseJson = String.isBlank(doc.Response_Json__c)
                    ? new Map<String, Object>()
                    : (Map<String, Object>) JSON.deserializeUntyped(doc.Response_Json__c);
            } catch (Exception ex2) {
                responseJson = new Map<String, Object>();
            }
    
            String sourceType = normalizeSourceType(firstNonBlank(
                safeString(doc.get('DocFlow_Source_Type__c')),
                safeString(config.get('sourceType'))
            ));
    
            List<RecipientInfo> recipients = parseRecipients(config);
            if (recipients.isEmpty()) {
                addDocError(docUpdatesById, doc.Id, 'Cadence skipped: no recipients found in Recipient_Config_Json__c.');
                continue;
            }

            if (isCompletedEvent(ctx)) {
    String completedAccessLink = extractCompletedAccessLink(
        responseJson,
        safeString(doc.get('Primary_Access_Link__c')),
        ctx.downloadUrl
    );

    if (!String.isBlank(completedAccessLink)) {
        Doc_Flow_Document__c completedUpd = docUpdatesById.containsKey(doc.Id)
            ? docUpdatesById.get(doc.Id)
            : new Doc_Flow_Document__c(Id = doc.Id);

        putIfFieldExists(completedUpd, 'Primary_Access_Link__c', completedAccessLink);

        if (!String.isBlank(ctx.downloadUrl)) {
            putIfFieldExists(completedUpd, 'Signed_Document_URL__c', ctx.downloadUrl);
        }

        docUpdatesById.put(doc.Id, completedUpd);

        addCompletedEmailWorkForAllRecipients(
            pendingEmailByKey,
            doc,
            config,
            recipients,
            completedAccessLink
        );
    } else {
        addDocError(
            docUpdatesById,
            doc.Id,
            'Completed email skipped: completed access link was blank.'
        );
    }

    docIdsToCancelReminders.add(doc.Id);
    continue;
}

    
            if (isSignedCopyEvent(ctx)) {
                for (RecipientInfo r : recipients) {
                    if (String.isBlank(r.email)) {
                        continue;
                    }
    
                    String key = doc.Id + '::completed::' + r.email.toLowerCase();
                    if (pendingEmailByKey.containsKey(key)) {
                        continue;
                    }
    
                    PendingEmailWork work = new PendingEmailWork();
                    work.syntheticKey = key;
                    work.docId = doc.Id;
                    work.accountId = doc.Account__c;
                    work.toEmail = r.email;
                    work.templateDeveloperName = TEMPLATE_COMPLETED_DEV_NAME;
                    work.fromAddressValue = extractFromAddressValue(config);
                    work.recipientName = r.name;
                    work.accessLink = null;
                    pendingEmailByKey.put(key, work);
                }
    
                docIdsToCancelReminders.add(doc.Id);
                continue;
            }
    
            if (isRejectedEvent(ctx)) {
                addDocError(docUpdatesById, doc.Id, 'Cadence stopped: approval/reject event was rejected.');
                docIdsToCancelReminders.add(doc.Id);
                continue;
            }
    
            Integer currentIndex = findRecipientIndex(recipients, ctx.actorEmail, ctx.actorRole);
RecipientInfo currentRecipient = currentIndex >= 0 ? recipients[currentIndex] : null;

if (currentIndex < 0 || !shouldAdvanceCadence(ctx, currentRecipient, sourceType)) {
    Integer linkMatchedIndex = findRecipientIndexByCurrentAccessLink(
        recipients,
        responseJson,
        safeString(doc.get('Primary_Access_Link__c'))
    );

    if (linkMatchedIndex >= 0) {
        RecipientInfo linkMatchedRecipient = recipients[linkMatchedIndex];

        if (shouldAdvanceCadence(ctx, linkMatchedRecipient, sourceType)) {
            currentIndex = linkMatchedIndex;
            currentRecipient = linkMatchedRecipient;
        }
    }
}

if (currentIndex < 0) {
    addDocError(
        docUpdatesById,
        doc.Id,
        'Cadence skipped: current recipient not matched by email/role/link. Email=' + blankToEmpty(ctx.actorEmail)
    );
    continue;
}

if (!shouldAdvanceCadence(ctx, currentRecipient, sourceType)) {
    addDocError(
        docUpdatesById,
        doc.Id,
        'Cadence skipped: event does not advance matched recipient. Event=' +
        blankToEmpty(ctx.eventType) +
        ', ActorEmail=' + blankToEmpty(ctx.actorEmail) +
        ', ActorRole=' + blankToEmpty(ctx.actorRole) +
        ', MatchedRole=' + blankToEmpty(currentRecipient.role)
    );
    continue;
}

Integer activeLinkIndex = findRecipientIndexByCurrentAccessLink(
    recipients,
    responseJson,
    safeString(doc.get('Primary_Access_Link__c'))
);

if (activeLinkIndex >= 0 && activeLinkIndex != currentIndex) {
    addDocError(
        docUpdatesById,
        doc.Id,
        'Cadence skipped: stale/duplicate webhook ignored. Event=' +
        blankToEmpty(ctx.eventType) +
        ', ActorEmail=' + blankToEmpty(ctx.actorEmail) +
        ', MatchedRole=' + blankToEmpty(currentRecipient.role)
    );
    continue;
}
    
RecipientInfo nextRecipient = findNextActionableRecipient(recipients, currentIndex);
            if (nextRecipient == null) {
                continue;
            }
    
            String templateDevName = templateForRole(nextRecipient.role);
            if (String.isBlank(templateDevName)) {
                addDocError(
                    docUpdatesById,
                    doc.Id,
                    'Cadence skipped: no template mapped for next recipient role ' + blankToEmpty(nextRecipient.role) + '.'
                );
                continue;
            }
    
            if (String.isBlank(nextRecipient.email)) {
                addDocError(docUpdatesById, doc.Id, 'Cadence skipped: next recipient email is blank.');
                continue;
            }
    
            String nextAccessLink = extractRecipientAccessLink(
                responseJson,
                nextRecipient.email,
                nextRecipient.sequence
            );
    
            if (String.isBlank(nextAccessLink)) {
                addDocError(
                    docUpdatesById,
                    doc.Id,
                    'Cadence skipped: next recipient access link missing for ' + nextRecipient.email + '.'
                );
                continue;
            }
    
            Doc_Flow_Document__c upd = new Doc_Flow_Document__c(Id = doc.Id);
            putIfFieldExists(upd, 'Primary_Access_Link__c', nextAccessLink);
            putIfFieldExists(upd, 'Recipient_Name_Value__c', nextRecipient.name);
            putIfFieldExists(upd, 'Recipient_Email_Value__c', nextRecipient.email);
            putIfFieldExists(upd, 'Recipient_Phone_Value__c', nextRecipient.phone);
            docUpdatesById.put(doc.Id, upd);
    
            String key = doc.Id + '::next::' + nextRecipient.email.toLowerCase();
            if (!pendingEmailByKey.containsKey(key)) {
                PendingEmailWork work = new PendingEmailWork();
                work.syntheticKey = key;
                work.docId = doc.Id;
                work.accountId = doc.Account__c;
                work.toEmail = nextRecipient.email;
                work.templateDeveloperName = templateDevName;
                work.fromAddressValue = extractFromAddressValue(config);
                work.recipientName = nextRecipient.name;
                work.accessLink = nextAccessLink;
                pendingEmailByKey.put(key, work);
            }
    
            if (!String.isBlank(nextRecipient.phone) && !String.isBlank(nextAccessLink)) {
                DocFlowSmsService.SmsWork smsWork = new DocFlowSmsService.SmsWork();
                smsWork.docId = doc.Id;
                smsWork.receiverNumber = nextRecipient.phone;
                smsWork.senderNumber = DocFlowSmsService.DEFAULT_SENDER_NUMBER;
                smsWork.messageBody = DocFlowSmsService.buildInitialSigningBody(nextAccessLink);
                smsWorkToSend.add(smsWork);
            }
    
            docIdsToCancelReminders.add(doc.Id);
    
            ReminderActivationWork reminderWork = new ReminderActivationWork();
            reminderWork.docId = doc.Id;
            reminderWork.recipientId = nextRecipient.recipientId;
            reminderWork.sequence = nextRecipient.sequence;
            reminderWork.role = nextRecipient.role;
            reminderWork.name = nextRecipient.name;
            reminderWork.email = nextRecipient.email;
            reminderWork.phone = nextRecipient.phone;
            reminderWork.accessLink = nextAccessLink;
            reminderActivationWork.add(reminderWork);
        }
    
        if (!docUpdatesById.isEmpty()) {
            Database.update(docUpdatesById.values(), false);
        }
    
        Map<Id, Account> accountMap = queryAccounts(accountIds);
    
        if (!pendingEmailByKey.isEmpty()) {
            sendEmails(new List<PendingEmailWork>(pendingEmailByKey.values()), accountMap);
        }
    
        if (!smsWorkToSend.isEmpty()) {
            DocFlowSmsService.sendInitialSmsBatch(smsWorkToSend);
        }
    
        for (Id docIdToCancel : docIdsToCancelReminders) {
            DocFlowReminderService.cancelPendingRemindersForDocument(docIdToCancel);
        }
    
        for (ReminderActivationWork rw : reminderActivationWork) {
            DocFlowReminderService.activateRecipientReminders(
                rw.docId,
                rw.recipientId,
                rw.sequence,
                rw.role,
                rw.name,
                rw.email,
                rw.phone,
                rw.accessLink
            );
        }
    }
    private static void addCompletedEmailWorkForAllRecipients(
    Map<String, PendingEmailWork> pendingEmailByKey,
    Doc_Flow_Document__c doc,
    Map<String, Object> config,
    List<RecipientInfo> recipients,
    String completedAccessLink
) {
    if (
        pendingEmailByKey == null ||
        doc == null ||
        doc.Id == null ||
        recipients == null ||
        recipients.isEmpty() ||
        String.isBlank(completedAccessLink)
    ) {
        return;
    }

    Set<String> addedEmails = new Set<String>();
    String fromAddressValue = extractFromAddressValue(config);

    for (RecipientInfo r : recipients) {
        if (r == null || String.isBlank(r.email)) {
            continue;
        }

        String lowerEmail = r.email.trim().toLowerCase();

        if (addedEmails.contains(lowerEmail)) {
            continue;
        }

        addedEmails.add(lowerEmail);

        String key = doc.Id + '::completed_final::' + lowerEmail;

        if (pendingEmailByKey.containsKey(key)) {
            continue;
        }

        PendingEmailWork work = new PendingEmailWork();
        work.syntheticKey = key;
        work.docId = doc.Id;
        work.accountId = doc.Account__c;
        work.toEmail = r.email;
        work.templateDeveloperName = TEMPLATE_COMPLETED_DEV_NAME;
        work.fromAddressValue = fromAddressValue;
        work.recipientName = r.name;
        work.accessLink = completedAccessLink;

        pendingEmailByKey.put(key, work);
    }
}

    private static void addDocError(
        Map<Id, Doc_Flow_Document__c> docUpdatesById,
        Id docId,
        String message
    ) {
        if (docId == null || String.isBlank(message)) {
            return;
        }

        Doc_Flow_Document__c upd = docUpdatesById.containsKey(docId)
            ? docUpdatesById.get(docId)
            : new Doc_Flow_Document__c(Id = docId);

        putIfFieldExists(upd, 'Error_Message__c', safeTrim(message, 32000));
        docUpdatesById.put(docId, upd);
    }

    private static Boolean isCompletedEvent(AnalyticsEventContext ctx) {
        return ctx != null && blankToEmpty(ctx.eventType).toLowerCase() == 'completed';
    }

    private static Boolean isSignedCopyEvent(AnalyticsEventContext ctx) {
        return ctx != null && blankToEmpty(ctx.eventType).toLowerCase() == 'signed_copy';
    }

    private static Boolean isRejectedEvent(AnalyticsEventContext ctx) {
        if (ctx == null) {
            return false;
        }
    
        String evt = blankToEmpty(ctx.eventType).toLowerCase();
        String action = blankToEmpty(ctx.action).toLowerCase();
    
        return evt == 'reject'
            || (evt == 'approve_reject' && action == 'rejected')
            || action == 'rejected';
    }

    private static Boolean shouldAdvanceCadence(
    AnalyticsEventContext ctx,
    RecipientInfo currentRecipient,
    String sourceType
) {
    if (ctx == null || currentRecipient == null) {
        return false;
    }

    String evt = blankToEmpty(ctx.eventType).toLowerCase();
    String action = blankToEmpty(ctx.action).toLowerCase();
    String role = blankToEmpty(currentRecipient.role).toLowerCase();
    String src = blankToEmpty(sourceType).toLowerCase();

    if (role == 'signer' && evt == 'signed') {
        return true;
    }

    if (role == 'approver') {
        if (evt == 'approve') {
            return true;
        }
        if (evt == 'approve_reject' && action == 'approved') {
            return true;
        }
        if (action == 'approved') {
            return true;
        }
    }

    if (role == 'reviewer') {
        if (src == 'template') {
            return evt == 'review' || action == 'reviewed';
        }
        return evt == 'opened' || evt == 'review' || action == 'reviewed';
    }

    return false;
}

    private static Integer findRecipientIndex(
        List<RecipientInfo> recipients,
        String actorEmail,
        String actorRole
    ) {
        if (recipients == null || recipients.isEmpty()) {
            return -1;
        }

        String lowerEmail = String.isBlank(actorEmail) ? null : actorEmail.toLowerCase();
        String lowerRole = String.isBlank(actorRole) ? null : actorRole.toLowerCase();
        Integer emailOnlyMatch = -1;

        for (Integer i = 0; i < recipients.size(); i++) {
            RecipientInfo r = recipients[i];
            if (r == null || String.isBlank(r.email)) {
                continue;
            }

            if (lowerEmail != null && r.email.toLowerCase() == lowerEmail) {
                if (lowerRole != null && !String.isBlank(r.role) && r.role.toLowerCase() == lowerRole) {
                    return i;
                }

                if (emailOnlyMatch < 0) {
                    emailOnlyMatch = i;
                }
            }
        }

        return emailOnlyMatch;
    }
    private static Integer findRecipientIndexByCurrentAccessLink(
    List<RecipientInfo> recipients,
    Map<String, Object> responseJson,
    String currentAccessLink
) {
    if (
        recipients == null ||
        recipients.isEmpty() ||
        responseJson == null ||
        String.isBlank(currentAccessLink)
    ) {
        return -1;
    }

    Object linksObj = responseJson.get('recipient_links');
    if (!(linksObj instanceof List<Object>)) {
        return -1;
    }

    String activeLink = currentAccessLink.trim();

    for (Object rowObj : (List<Object>) linksObj) {
        if (!(rowObj instanceof Map<String, Object>)) {
            continue;
        }

        Map<String, Object> row = (Map<String, Object>) rowObj;

        String accessLink = normalizeText(safeString(row.get('access_link')));
        String signingLink = normalizeText(safeString(row.get('signing_link')));
        String viewerLink = normalizeText(safeString(row.get('viewer_link')));

        Boolean isMatchedLink =
            (!String.isBlank(accessLink) && accessLink == activeLink) ||
            (!String.isBlank(signingLink) && signingLink == activeLink) ||
            (!String.isBlank(viewerLink) && viewerLink == activeLink);

        if (!isMatchedLink) {
            continue;
        }

        String linkEmail = normalizeText(safeString(row.get('email')));
        Integer routingOrder = normalizeInteger(row.get('routing_order'));

        if (routingOrder != null) {
            for (Integer i = 0; i < recipients.size(); i++) {
                RecipientInfo r = recipients[i];
                if (r != null && r.sequence != null && r.sequence == routingOrder) {
                    return i;
                }
            }
        }

        if (!String.isBlank(linkEmail)) {
            for (Integer i = 0; i < recipients.size(); i++) {
                RecipientInfo r = recipients[i];
                if (
                    r != null &&
                    !String.isBlank(r.email) &&
                    r.email.toLowerCase() == linkEmail.toLowerCase()
                ) {
                    return i;
                }
            }
        }
    }

    return -1;
}

private static RecipientInfo findNextActionableRecipient(List<RecipientInfo> recipients, Integer currentIndex) {
    if (recipients == null || currentIndex == null) {
        return null;
    }

    for (Integer i = currentIndex + 1; i < recipients.size(); i++) {
        RecipientInfo next = recipients[i];
        if (next == null) {
            continue;
        }

        if (String.isBlank(next.email)) {
            continue;
        }

        return next;
    }

    return null;
}

    private static List<RecipientInfo> parseRecipients(Map<String, Object> config) {
        List<RecipientInfo> recipients = new List<RecipientInfo>();

        if (config == null || !config.containsKey('recipients')) {
            return recipients;
        }

        List<Object> rows = (List<Object>) config.get('recipients');
        if (rows == null) {
            return recipients;
        }

        for (Object rowObj : rows) {
            if (!(rowObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) rowObj;

            RecipientInfo r = new RecipientInfo();
            r.recipientId = normalizeText(safeString(row.get('recipientId')));
            r.sequence = normalizeInteger(row.get('sequence'));
            r.role = normalizeText(safeString(row.get('role')));
            r.name = extractResolvedValue(row.get('name'));
            r.email = extractResolvedValue(row.get('email'));
            r.phone = extractResolvedValue(row.get('phone'));

            recipients.add(r);
        }

        recipients.sort();
        return recipients;
    }

    private static String extractResolvedValue(Object section) {
        if (section == null) {
            return null;
        }

        if (section instanceof Map<String, Object>) {
            Map<String, Object> sectionMap = (Map<String, Object>) section;
            return normalizeText(safeString(sectionMap.get('resolvedValue')));
        }

        return normalizeText(safeString(section));
    }

    private static String extractFromAddressValue(Map<String, Object> config) {
        if (config == null || !config.containsKey('fromAddress')) {
            return null;
        }

        Object fromAddressObj = config.get('fromAddress');
        if (!(fromAddressObj instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> fromAddress = (Map<String, Object>) fromAddressObj;
        return normalizeText(safeString(fromAddress.get('value')));
    }

    private static String extractRecipientAccessLink(
        Map<String, Object> responseJson,
        String recipientEmail,
        Integer sequence
    ) {
        if (responseJson == null) {
            return null;
        }

        List<Object> links = (List<Object>) responseJson.get('recipient_links');
        if (links != null) {
            String lowerEmail = String.isBlank(recipientEmail) ? null : recipientEmail.toLowerCase();

            for (Object rowObj : links) {
                if (!(rowObj instanceof Map<String, Object>)) {
                    continue;
                }

                Map<String, Object> row = (Map<String, Object>) rowObj;
                String email = normalizeText(safeString(row.get('email')));
                Integer routingOrder = normalizeInteger(row.get('routing_order'));

                if (lowerEmail != null && !String.isBlank(email) && email.toLowerCase() == lowerEmail) {
                    if (sequence == null || routingOrder == null || routingOrder == sequence) {
                        return normalizeText(safeString(row.get('access_link')));
                    }
                }
            }

            if (sequence != null) {
                for (Object rowObj : links) {
                    if (!(rowObj instanceof Map<String, Object>)) {
                        continue;
                    }

                    Map<String, Object> row = (Map<String, Object>) rowObj;
                    Integer routingOrder = normalizeInteger(row.get('routing_order'));
                    if (routingOrder != null && routingOrder == sequence) {
                        return normalizeText(safeString(row.get('access_link')));
                    }
                }
            }
        }

        return normalizeText(safeString(responseJson.get('public_link')));
    }

    private static String extractCompletedAccessLink(
    Map<String, Object> responseJson,
    String currentPrimaryAccessLink,
    String downloadUrl
) {
    if (responseJson != null) {
        Object linksObj = responseJson.get('recipient_links');

        if (linksObj instanceof List<Object>) {
            List<Object> links = (List<Object>) linksObj;

            // Prefer receive_copy link because it is a view/download style link.
            for (Object rowObj : links) {
                if (!(rowObj instanceof Map<String, Object>)) {
                    continue;
                }

                Map<String, Object> row = (Map<String, Object>) rowObj;
                String role = blankToEmpty(safeString(row.get('role'))).toLowerCase();

                if (role == 'receive_copy' || role == 'receive copy') {
                    String link = normalizeText(firstNonBlank(
                        safeString(row.get('access_link')),
                        safeString(row.get('viewer_link'))
                    ));

                    if (!String.isBlank(link)) {
                        return link;
                    }
                }
            }

            // If receive_copy is not present, use the last available recipient link.
            for (Integer i = links.size() - 1; i >= 0; i--) {
                Object rowObj = links[i];

                if (!(rowObj instanceof Map<String, Object>)) {
                    continue;
                }

                Map<String, Object> row = (Map<String, Object>) rowObj;

                String link = normalizeText(firstNonBlank(
                    safeString(row.get('access_link')),
                    safeString(row.get('viewer_link'))
                ));

                if (!String.isBlank(link)) {
                    return link;
                }
            }
        }

        String publicLink = normalizeText(safeString(responseJson.get('public_link')));
        if (!String.isBlank(publicLink)) {
            return publicLink;
        }
    }

    if (!String.isBlank(currentPrimaryAccessLink)) {
        return currentPrimaryAccessLink;
    }

    return normalizeText(downloadUrl);
}

   private static void sendEmails(List<PendingEmailWork> workItems, Map<Id, Account> accountMap) {
    if (workItems == null || workItems.isEmpty()) {
        return;
    }

    Map<String, Id> templateIdsByDevName = getTemplateIdsByDeveloperNames(
        new Set<String>{
            TEMPLATE_SEND_DEV_NAME,
            TEMPLATE_APPROVAL_DEV_NAME,
            TEMPLATE_REVIEW_DEV_NAME,
            TEMPLATE_COMPLETED_DEV_NAME
        }
    );

    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    List<PendingEmailWork> sendOrder = new List<PendingEmailWork>();

    Map<Id, Doc_Flow_Document__c> immediateErrorsByDocId = new Map<Id, Doc_Flow_Document__c>();

    for (PendingEmailWork work : workItems) {
        if (work == null || work.docId == null) {
            continue;
        }

        if (String.isBlank(work.templateDeveloperName)) {
            addDocError(
                immediateErrorsByDocId,
                work.docId,
                'Cadence email not sent: template developer name was blank.'
            );
            continue;
        }

        if (String.isBlank(work.toEmail)) {
            addDocError(
                immediateErrorsByDocId,
                work.docId,
                'Cadence email not sent: recipient email was blank.'
            );
            continue;
        }

        Account acc = accountMap.get(work.accountId);
        if (acc == null || acc.PersonContactId == null) {
            addDocError(
                immediateErrorsByDocId,
                work.docId,
                'Cadence email not sent: PersonContactId is blank on the related Person Account.'
            );
            continue;
        }

        Id templateId = templateIdsByDevName.get(work.templateDeveloperName);
        if (templateId == null) {
            addDocError(
                immediateErrorsByDocId,
                work.docId,
                'Cadence email not sent: template not found for developer name ' +
                work.templateDeveloperName + '.'
            );
            continue;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTemplateId(templateId);
        mail.setTargetObjectId(acc.PersonContactId);
        mail.setTreatTargetObjectAsRecipient(false);
        mail.setToAddresses(new String[]{ work.toEmail });
        mail.setWhatId(work.docId);
        mail.setSaveAsActivity(false);

        if (!String.isBlank(work.fromAddressValue) && work.fromAddressValue.startsWith('OWEA:')) {
            mail.setOrgWideEmailAddressId(work.fromAddressValue.substring(5));
        }

        emails.add(mail);
        sendOrder.add(work);
    }

    if (!immediateErrorsByDocId.isEmpty()) {
        Database.update(immediateErrorsByDocId.values(), false);
    }

    if (emails.isEmpty()) {
        return;
    }

    try {
        Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

        Map<Id, Doc_Flow_Document__c> sendFailuresByDocId = new Map<Id, Doc_Flow_Document__c>();

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                PendingEmailWork failedWork = sendOrder[i];
                addDocError(
                    sendFailuresByDocId,
                    failedWork.docId,
                    buildEmailSendErrorMessage(
                        failedWork.templateDeveloperName,
                        failedWork.toEmail,
                        results[i]
                    )
                );
            }
        }

        if (!sendFailuresByDocId.isEmpty()) {
            Database.update(sendFailuresByDocId.values(), false);
        }

    } catch (Exception ex) {
        Map<Id, Doc_Flow_Document__c> fatalErrorsByDocId = new Map<Id, Doc_Flow_Document__c>();

        for (PendingEmailWork work : sendOrder) {
            addDocError(
                fatalErrorsByDocId,
                work.docId,
                safeTrim(
                    'Cadence email send failed with exception: ' + ex.getMessage(),
                    32000
                )
            );
        }

        if (!fatalErrorsByDocId.isEmpty()) {
            Database.update(fatalErrorsByDocId.values(), false);
        }
    }
}
    private static String buildEmailSendErrorMessage(
        String templateDeveloperName,
        String toEmail,
        Messaging.SendEmailResult result
    ) {
        String message =
            'Cadence email send failed. Template=' + templateDeveloperName +
            ', To=' + toEmail + '. ';

        if (result != null && result.getErrors() != null) {
            for (Messaging.SendEmailError err : result.getErrors()) {
                message +=
                    'StatusCode=' + String.valueOf(err.getStatusCode()) +
                    ', Message=' + err.getMessage() + ' | ';
            }
        }

        return safeTrim(message, 32000);
    }

    private static Map<String, Id> getTemplateIdsByDeveloperNames(Set<String> developerNames) {
        Map<String, Id> result = new Map<String, Id>();

        for (EmailTemplate t : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :developerNames
        ]) {
            result.put(t.DeveloperName, t.Id);
        }

        return result;
    }

    private static Map<Id, Account> queryAccounts(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }

        return new Map<Id, Account>([
            SELECT Id, PersonContactId
            FROM Account
            WHERE Id IN :accountIds
        ]);
    }

    private static String templateForRole(String role) {
    String normalizedRole = blankToEmpty(role).toLowerCase();

    if (normalizedRole == 'signer') {
        return TEMPLATE_SEND_DEV_NAME;
    }
    if (normalizedRole == 'approver') {
        return TEMPLATE_APPROVAL_DEV_NAME;
    }
    if (normalizedRole == 'reviewer') {
        return TEMPLATE_REVIEW_DEV_NAME;
    }
    if (normalizedRole == 'receive_copy') {
        return TEMPLATE_COMPLETED_DEV_NAME;
    }

    return null;
}
    private static String normalizeSourceType(String value) {
        return String.isBlank(value) ? null : value.trim().toLowerCase();
    }

    private static String inferRoleFromPayload(String eventType, String action) {
        String evt = blankToEmpty(eventType).toLowerCase();
        String act = blankToEmpty(action).toLowerCase();
    
        if (evt == 'approve' || evt == 'reject' || evt == 'approve_reject' || act == 'approved' || act == 'rejected') {
            return 'approver';
        }
        if (evt == 'review' || evt == 'opened' || act == 'reviewed') {
            return 'reviewer';
        }
        if (evt == 'signed') {
            return 'signer';
        }
        return null;
    }

    private static String firstNonBlank(String value1, String value2) {
        return !String.isBlank(value1) ? value1 : value2;
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

    private static Integer normalizeInteger(Object value) {
        if (value == null) return null;
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Long) return Integer.valueOf(String.valueOf(value));
        if (value instanceof Decimal) return ((Decimal) value).intValue();
        return Integer.valueOf(String.valueOf(value));
    }

    private static String normalizeText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
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

    private static void putIfFieldExists(SObject sobj, String fieldApi, Object value) {
        if (sobj == null || String.isBlank(fieldApi)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap =
            sobj.getSObjectType().getDescribe().fields.getMap();

        if (fieldMap.containsKey(fieldApi)) {
            sobj.put(fieldApi, value);
        }
    }

    public class AnalyticsEventContext {
        public Id analyticsId;
        public Map<String, Object> rawPayload;
        public String eventType;
        public String action;
        public String packageId;
        public String documentId;
        public String actorEmail;
        public String actorName;
        public String actorRole;
        public Id personAccountId;
        public String sourceRecordId;
        public String downloadUrl;
        public Id docFlowDocumentId;
    }

    public class PendingEmailWork {
        public String syntheticKey;
        public Id docId;
        public Id accountId;
        public String toEmail;
        public String templateDeveloperName;
        public String fromAddressValue;
        public String recipientName;
        public String accessLink;
    }
    public class ReminderActivationWork {
    public Id docId;
    public String recipientId;
    public Integer sequence;
    public String role;
    public String name;
    public String email;
    public String phone;
    public String accessLink;
}

    public class RecipientInfo implements Comparable {
        public String recipientId;
        public Integer sequence;
        public String role;
        public String name;
        public String email;
        public String phone;

        public Integer compareTo(Object otherObj) {
            RecipientInfo other = (RecipientInfo) otherObj;
            Integer thisSeq = this.sequence == null ? 0 : this.sequence;
            Integer otherSeq = (other == null || other.sequence == null) ? 0 : other.sequence;

            if (thisSeq == otherSeq) {
                return 0;
            }
            return thisSeq < otherSeq ? -1 : 1;
        }
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
    
 public static void testRunMethod33() {
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

    public static void testRunMethod4() {
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
public static void testRunMethod5() {
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

public static void testRunMethod6() {
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