public with sharing class DocFlowDocumentProcessor {

    private static Boolean isRunning = false;

    private static final String PACKAGE_ENDPOINT  = 'https://api.cluvik.com/api/public/packages/send';
private static final String TEMPLATE_ENDPOINT = 'https://api.cluvik.com/api/v1/documents/generate-links';

private static final String DOC_SOURCE_TYPE_FIELD            = 'DocFlow_Source_Type__c';
private static final String DOC_PACKAGE_METADATA_JSON_FIELD  = 'Package_Metadata_Json__c';
private static final String DOC_TEMPLATE_METADATA_JSON_FIELD = 'Template_Metadata_Json__c';

private static final String SOURCE_TYPE_PACKAGE  = 'package';
private static final String SOURCE_TYPE_TEMPLATE = 'template';
    private static final String API_KEY = 'dfk_AeSCS10hxyricKBkgudeuCyW5y09MRN8gaNcpCGzIOI';

    private static final String STATUS_INITIATED   = 'initiated';
    private static final String STATUS_IN_PROGRESS = 'in_progress';
    private static final String STATUS_SUCCESS     = 'success';
    private static final String STATUS_FAILED      = 'failed';

    private static final String TEMPLATE_SEND_DEV_NAME      = 'Docflow_Send_Template';
    private static final String TEMPLATE_APPROVAL_DEV_NAME  = 'Docflow_Approval_Email';
    private static final String TEMPLATE_REVIEW_DEV_NAME    = 'Docflow_Review_Email';
    private static final String TEMPLATE_COMPLETED_DEV_NAME = 'Completed_Docflow_Template';
    private static final String DOCFLOW_FROM_NAME = 'BatonCare Team';
private static final String DOCFLOW_FROM_EMAIL = 'support@batoncare.com';

    public static void handleAfter(
        List<Doc_Flow_Document__c> newList,
        Map<Id, Doc_Flow_Document__c> oldMap
    ) {
        if (isRunning) {
            return;
        }

        isRunning = true;
        try {
            Set<Id> processIds = new Set<Id>();
            List<Doc_Flow_Document__c> statusUpdates = new List<Doc_Flow_Document__c>();

            for (Doc_Flow_Document__c rec : newList) {
                if (shouldProcess(rec, oldMap)) {
                    processIds.add(rec.Id);
                    statusUpdates.add(new Doc_Flow_Document__c(
                        Id = rec.Id,
                        Status__c = STATUS_IN_PROGRESS,
                        Error_Message__c = null
                    ));
                }
            }

            if (!statusUpdates.isEmpty()) {
                update statusUpdates;
            }

            if (!processIds.isEmpty()) {
                System.enqueueJob(new DocFlowSendQueueable(new List<Id>(processIds)));
            }
        } finally {
            isRunning = false;
        }
    }

    private static Boolean shouldProcess(
    Doc_Flow_Document__c rec,
    Map<Id, Doc_Flow_Document__c> oldMap
) {
    if (rec == null) {
        return false;
    }

    if (rec.Status__c != STATUS_INITIATED) {
        return false;
    }

    if (rec.Account__c == null || String.isBlank(rec.Template_Id__c) || String.isBlank(rec.Recipient_Config_Json__c)) {
        return false;
    }

    String sourceType = normalizeSourceType(safeString(rec.get(DOC_SOURCE_TYPE_FIELD)));
    if (String.isBlank(sourceType)) {
        return false;
    }

    if (isPackageSource(sourceType) && String.isBlank(safeString(rec.get(DOC_PACKAGE_METADATA_JSON_FIELD)))) {
        return false;
    }

    if (isTemplateSource(sourceType) && String.isBlank(safeString(rec.get(DOC_TEMPLATE_METADATA_JSON_FIELD)))) {
        return false;
    }

    if (oldMap == null || !oldMap.containsKey(rec.Id)) {
        return true;
    }

    Doc_Flow_Document__c oldRec = oldMap.get(rec.Id);
    return oldRec == null || oldRec.Status__c != STATUS_INITIATED;
}
private static String normalizeSourceType(String sourceType) {
    return String.isBlank(sourceType) ? null : sourceType.trim().toLowerCase();
}

private static Boolean isPackageSource(String sourceType) {
    return normalizeSourceType(sourceType) == SOURCE_TYPE_PACKAGE;
}

private static Boolean isTemplateSource(String sourceType) {
    return normalizeSourceType(sourceType) == SOURCE_TYPE_TEMPLATE;
}

    public class DocFlowSendQueueable implements Queueable, Database.AllowsCallouts {
        private final List<Id> recordIds;

        public DocFlowSendQueueable(List<Id> recordIds) {
            this.recordIds = recordIds;
        }

        public void execute(QueueableContext context) {
            List<Doc_Flow_Document__c> docs = [
                SELECT Id,
                       Account__c,
                       Template_Id__c,
                       Status__c,
                       Request_Json__c,
                       Response_Json__c,
                       Document_Id__c,
                       Document_Name__c,
                       Primary_Access_Link__c,
                       Error_Message__c,
                       Recipient_Config_Json__c,
                       Package_Metadata_Json__c,
                       Template_Metadata_Json__c,
                       DocFlow_Source_Type__c
                FROM Doc_Flow_Document__c
                WHERE Id IN :recordIds
            ];
        
            List<Doc_Flow_Document__c> updates = new List<Doc_Flow_Document__c>();
            Map<Id, InitialEmailWork> emailWorkByDocId = new Map<Id, InitialEmailWork>();
            Map<Id, DocFlowSmsService.SmsWork> smsWorkByDocId = new Map<Id, DocFlowSmsService.SmsWork>();
            Map<Id, Doc_Flow_Document__c> updateById = new Map<Id, Doc_Flow_Document__c>();
        
            for (Doc_Flow_Document__c doc : docs) {
                Doc_Flow_Document__c upd = new Doc_Flow_Document__c(Id = doc.Id);
                String requestBody;
        
                try {
                    Account acc = queryAccountForDoc(doc);
                    if (acc == null) {
                        throw new IllegalArgumentException('Related Account was not found.');
                    }
        
                    PayloadBuildResult buildResult = buildPayload(doc, acc);
                    requestBody = JSON.serialize(buildResult.payload);
        
                    String sourceType = normalizeSourceType(safeString(doc.get(DOC_SOURCE_TYPE_FIELD)));
                    String endpoint = isTemplateSource(sourceType) ? TEMPLATE_ENDPOINT : PACKAGE_ENDPOINT;
        
                    HttpRequest req = new HttpRequest();
                    req.setEndpoint(endpoint);
                    req.setMethod('POST');
                    req.setHeader('X-API-Key', API_KEY);
                    req.setHeader('Content-Type', 'application/json');
                    req.setTimeout(120000);
                    req.setBody(requestBody);
        
                    HttpResponse res = new Http().send(req);
        
                    upd.Request_Json__c = requestBody;
                    upd.Response_Json__c = res.getBody();
        
                    if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        
                        Boolean successFlag = root.containsKey('success')
                            ? normalizeBoolean(root.get('success'))
                            : false;
        
                        if (successFlag) {
                            upd.Status__c = STATUS_SUCCESS;
                            upd.Error_Message__c = null;
        
                            mapSuccessFields(upd, root);
                            String packageRuntimeId = normalizeText(firstNonBlank(
    safeString(root.get('run_id')),
    safeString(root.get('package_id'))
));

if (!String.isBlank(packageRuntimeId)) {
    putIfFieldExists(upd, 'Package_Runtime_Id__c', packageRuntimeId);
}
        
                            String firstAccessLink = extractRecipientAccessLink(
                                root,
                                buildResult.firstRecipientEmail
                            );
        
                            if (!String.isBlank(firstAccessLink)) {
                                putIfFieldExists(upd, 'Primary_Access_Link__c', firstAccessLink);
                            }
        
                            if (!String.isBlank(buildResult.firstRecipientName)) {
                                putIfFieldExists(upd, 'Recipient_Name_Value__c', buildResult.firstRecipientName);
                            }
        
                            if (!String.isBlank(buildResult.firstRecipientEmail)) {
                                putIfFieldExists(upd, 'Recipient_Email_Value__c', buildResult.firstRecipientEmail);
                            }
        
                            if (!String.isBlank(buildResult.firstRecipientPhone)) {
                                putIfFieldExists(upd, 'Recipient_Phone_Value__c', buildResult.firstRecipientPhone);
                            }
        
                            String initialTemplateDevName = templateForInitialRole(buildResult.firstRecipientRole);
        
                            if (!String.isBlank(initialTemplateDevName)
                                && !String.isBlank(firstAccessLink)
                                && !String.isBlank(buildResult.firstRecipientEmail)) {
        
                                Id targetContactId = acc.PersonContactId;
        
                                if (targetContactId == null) {
                                    upd.Status__c = STATUS_FAILED;
                                    upd.Error_Message__c =
                                        'Initial email not sent: PersonContactId is blank on the related Person Account.';
                                } else {
                                    InitialEmailWork work = new InitialEmailWork();
                                    work.docId = doc.Id;
                                    work.toEmail = buildResult.firstRecipientEmail;
                                    work.role = buildResult.firstRecipientRole;
                                    work.templateDeveloperName = initialTemplateDevName;
                                    work.fromAddressValue = buildResult.fromAddressValue;
                                    work.targetContactId = targetContactId;
                                    emailWorkByDocId.put(doc.Id, work);
                                }
                            }
        
                            if (!String.isBlank(buildResult.firstRecipientPhone) && !String.isBlank(firstAccessLink)) {
                                DocFlowSmsService.SmsWork smsWork = new DocFlowSmsService.SmsWork();
                                smsWork.docId = doc.Id;
                                smsWork.receiverNumber = buildResult.firstRecipientPhone;
                                smsWork.senderNumber = DocFlowSmsService.DEFAULT_SENDER_NUMBER;
                                smsWork.messageBody = DocFlowSmsService.buildInitialSigningBody(firstAccessLink);
                                smsWorkByDocId.put(doc.Id, smsWork);
                            }
                        } else {
                            upd.Status__c = STATUS_FAILED;
                            upd.Error_Message__c = extractFailureMessage(root, res);
                        }
                    } else {
                        upd.Status__c = STATUS_FAILED;
                        upd.Error_Message__c =
                            'HTTP ' + res.getStatusCode() + ' - ' + res.getStatus() +
                            ' | ' + safeTrim(res.getBody(), 32000);
                    }
                } catch (Exception ex) {
                    upd.Status__c = STATUS_FAILED;
                    upd.Error_Message__c = safeTrim(ex.getMessage(), 32000);
        
                    if (requestBody != null) {
                        upd.Request_Json__c = requestBody;
                    }
                }
        
                updates.add(upd);
                updateById.put(upd.Id, upd);
            }
        
            List<InitialEmailWork> emailWorkToSend = new List<InitialEmailWork>();
            List<DocFlowSmsService.SmsWork> smsWorkToSend = new List<DocFlowSmsService.SmsWork>();
            List<Doc_Flow_Document__c> reminderDocsToActivate = new List<Doc_Flow_Document__c>();
        
            if (!updates.isEmpty()) {
                Database.SaveResult[] saveResults = Database.update(updates, false);
        
                for (Integer i = 0; i < saveResults.size(); i++) {
                    if (saveResults[i].isSuccess()) {
                        Id updatedId = updates[i].Id;
        
                        if (emailWorkByDocId.containsKey(updatedId)) {
                            emailWorkToSend.add(emailWorkByDocId.get(updatedId));
                        }
        
                        if (smsWorkByDocId.containsKey(updatedId)) {
                            smsWorkToSend.add(smsWorkByDocId.get(updatedId));
                        }
        
                        if (updateById.containsKey(updatedId)) {
                            reminderDocsToActivate.add(updateById.get(updatedId));
                        }
                    }
                }
            }
        
            if (!emailWorkToSend.isEmpty()) {
                sendInitialEmails(emailWorkToSend);
            }
        
            if (!smsWorkToSend.isEmpty()) {
                DocFlowSmsService.sendInitialSmsBatch(smsWorkToSend);
            }
        
            if (!reminderDocsToActivate.isEmpty()) {
                DocFlowReminderService.activateInitialRecipientReminders(reminderDocsToActivate);
            }
        }
    }

    public class InitialEmailWork {
        public Id docId;
        public String toEmail;
        public String role;
        public String templateDeveloperName;
        public String fromAddressValue;
        public Id targetContactId;
    }

    public class PayloadBuildResult {
        public Map<String, Object> payload;
        public String firstRecipientEmail;
        public String firstRecipientName;
        public String firstRecipientRole;
        public String fromAddressValue;
        public String firstRecipientPhone;
    }

    private static PayloadBuildResult buildPayload(Doc_Flow_Document__c doc, Account acc) {
        String sourceType = normalizeSourceType(safeString(doc.get(DOC_SOURCE_TYPE_FIELD)));
    
        if (isTemplateSource(sourceType)) {
            return buildTemplatePayload(doc, acc);
        }
    
        return buildPackagePayload(doc, acc);
    }
    
    private static PayloadBuildResult buildPackagePayload(Doc_Flow_Document__c doc, Account acc) {
        Map<String, Object> config =
            (Map<String, Object>) JSON.deserializeUntyped(doc.Recipient_Config_Json__c);
    
        if (config == null) {
            throw new IllegalArgumentException('Recipient_Config_Json__c is invalid.');
        }
    
        Map<String, Object> packageMetadata =
            (Map<String, Object>) JSON.deserializeUntyped(doc.Package_Metadata_Json__c);
    
        if (packageMetadata == null) {
            throw new IllegalArgumentException('Package_Metadata_Json__c is invalid.');
        }
    
        String sourceType = normalizeText(safeString(config.get('sourceType')));
        if (!String.isBlank(sourceType) && sourceType.toLowerCase() != 'package') {
            throw new IllegalArgumentException('Only package-based configuration is supported.');
        }
    
        String packageIdFromConfig = normalizeText(safeString(config.get('packageId')));
        String packageId = !String.isBlank(packageIdFromConfig) ? packageIdFromConfig : doc.Template_Id__c;
    
        if (String.isBlank(packageId)) {
            throw new IllegalArgumentException('Package id is missing.');
        }
    
        Map<String, Object> fromAddress = (Map<String, Object>) config.get('fromAddress');
        String fromAddressValue = fromAddress == null ? null : safeString(fromAddress.get('value'));
    
        List<Object> recipientsRaw = (List<Object>) config.get('recipients');
        if (recipientsRaw == null || recipientsRaw.isEmpty()) {
            throw new IllegalArgumentException('At least one recipient is required.');
        }
    
        List<Object> apiRecipients = new List<Object>();
        Boolean smsConsent = false;
    
        String firstRecipientEmail = null;
        String firstRecipientName = null;
        String firstRecipientRole = null;
        String firstRecipientPhone = null;
        Integer firstRecipientSequence = null;
    
        Boolean hasSigner = false;
    
        for (Object row : recipientsRaw) {
            if (!(row instanceof Map<String, Object>)) {
                throw new IllegalArgumentException('Recipient row is invalid.');
            }
    
            Map<String, Object> recipient = (Map<String, Object>) row;
    
            String role = normalizeRoleForApi(safeString(recipient.get('role')));
            String recipientId = normalizeText(safeString(recipient.get('recipientId')));
            Integer sequence = normalizeInteger(recipient.get('sequence'));
    
            Map<String, Object> nameMap = (Map<String, Object>) recipient.get('name');
            Map<String, Object> emailMap = (Map<String, Object>) recipient.get('email');
            Map<String, Object> phoneMap = (Map<String, Object>) recipient.get('phone');
    
            String name = extractResolvedValue(nameMap);
            String email = extractResolvedValue(emailMap);
            String phone = extractResolvedValue(phoneMap);
    
            if (String.isBlank(role)) {
                throw new IllegalArgumentException('Recipient role is invalid.');
            }
            if (String.isBlank(recipientId)) {
                throw new IllegalArgumentException('Recipient id is missing.');
            }
            if (sequence == null) {
                throw new IllegalArgumentException('Recipient sequence is missing.');
            }
            if (String.isBlank(name)) {
                throw new IllegalArgumentException('Recipient name is required.');
            }
            if (String.isBlank(email) && String.isBlank(phone)) {
                throw new IllegalArgumentException('At least one of recipient email or phone is required.');
            }
    
            if (role == 'signer') {
                hasSigner = true;
            }
    
            if (firstRecipientSequence == null || sequence < firstRecipientSequence) {
                firstRecipientSequence = sequence;
                firstRecipientName = name;
                firstRecipientEmail = email;
                firstRecipientRole = role;
                firstRecipientPhone = phone;
            }
    
            Map<String, Object> apiRecipient = new Map<String, Object>{
                'id' => recipientId,
                'name' => name,
                'role' => role,
                'routing_order' => sequence,
                'wave' => sequence
            };
    
            if (!String.isBlank(email)) {
                apiRecipient.put('email', email);
            }
    
            if (!String.isBlank(phone)) {
                apiRecipient.put('phone', phone);
                smsConsent = true;
            }
    
            apiRecipients.add(apiRecipient);
        }
    
        if (!hasSigner) {
            throw new IllegalArgumentException('At least one signer is required.');
        }
    
        Map<String, Object> payload = new Map<String, Object>{
    'package_id' => packageId,
    'routing_mode' => 'sequential',
    'delivery_mode' => 'public_recipients',
    'sms_mode' => false,
    'sms_consent' => smsConsent,
    'expires_at' => null,
    'from_name' => DOCFLOW_FROM_NAME,
    'from_email' => DOCFLOW_FROM_EMAIL,
    'recipients' => apiRecipients,
    'field_assignments' => buildDynamicFieldAssignments((List<Object>) config.get('fieldAssignments')),
    'template_merge_fields' => buildDynamicTemplateMergeFields(packageMetadata, acc),
    'authentication' => new Map<String, Object>{
        'otp_required' => false
    },
    'metadata' => new Map<String, Object>{
        'record_id' => String.valueOf(acc.Id),
        'object_type' => 'Account',
        'source' => 'salesforce'
    }
};
    
        PayloadBuildResult result = new PayloadBuildResult();
        result.payload = payload;
        result.firstRecipientEmail = firstRecipientEmail;
        result.firstRecipientName = firstRecipientName;
        result.firstRecipientRole = firstRecipientRole;
        result.fromAddressValue = fromAddressValue;
        result.firstRecipientPhone = firstRecipientPhone;
        return result;
    }
    
    private static PayloadBuildResult buildTemplatePayload(Doc_Flow_Document__c doc, Account acc) {
        Map<String, Object> config =
            (Map<String, Object>) JSON.deserializeUntyped(doc.Recipient_Config_Json__c);
    
        if (config == null) {
            throw new IllegalArgumentException('Recipient_Config_Json__c is invalid.');
        }
    
        Map<String, Object> templateMetadata =
            (Map<String, Object>) JSON.deserializeUntyped(doc.Template_Metadata_Json__c);
    
        if (templateMetadata == null) {
            throw new IllegalArgumentException('Template_Metadata_Json__c is invalid.');
        }
    
        String sourceType = normalizeText(safeString(config.get('sourceType')));
        if (!String.isBlank(sourceType) && sourceType.toLowerCase() != 'template') {
            throw new IllegalArgumentException('Only template-based configuration is supported.');
        }
    
        String templateIdFromConfig = normalizeText(safeString(config.get('templateId')));
        String templateId = !String.isBlank(templateIdFromConfig) ? templateIdFromConfig : doc.Template_Id__c;
    
        if (String.isBlank(templateId)) {
            throw new IllegalArgumentException('Template id is missing.');
        }
    
        String documentName = normalizeText(safeString(config.get('templateName')));
        if (String.isBlank(documentName)) {
            documentName = normalizeText(safeString(templateMetadata.get('templateName')));
        }
        if (String.isBlank(documentName)) {
            documentName = !String.isBlank(doc.Document_Name__c) ? doc.Document_Name__c : 'DocFlow Template';
        }
    
        Map<String, Object> fromAddress = (Map<String, Object>) config.get('fromAddress');
        String fromAddressValue = fromAddress == null ? null : safeString(fromAddress.get('value'));
    
        List<Object> recipientsRaw = (List<Object>) config.get('recipients');
        if (recipientsRaw == null || recipientsRaw.isEmpty()) {
            throw new IllegalArgumentException('At least one recipient is required.');
        }
    
        Map<String, List<String>> assignedComponentsByRecipient = buildTemplateAssignedComponents(config);
        Map<String, Object> mergeFields = buildTemplateMergeFields(templateMetadata, acc, templateId);
    
        List<Object> apiRecipients = new List<Object>();
        Boolean smsConsent = false;
    
        String firstRecipientEmail = null;
        String firstRecipientName = null;
        String firstRecipientRole = null;
        String firstRecipientPhone = null;
        Integer firstRecipientSequence = null;
    
        Boolean hasSigner = false;
    
        for (Object row : recipientsRaw) {
            if (!(row instanceof Map<String, Object>)) {
                throw new IllegalArgumentException('Recipient row is invalid.');
            }
    
            Map<String, Object> recipient = (Map<String, Object>) row;
    
            String role = normalizeRoleForApi(safeString(recipient.get('role')));
            String recipientId = normalizeText(safeString(recipient.get('recipientId')));
            Integer sequence = normalizeInteger(recipient.get('sequence'));
    
            Map<String, Object> nameMap = (Map<String, Object>) recipient.get('name');
            Map<String, Object> emailMap = (Map<String, Object>) recipient.get('email');
            Map<String, Object> phoneMap = (Map<String, Object>) recipient.get('phone');
    
            String name = extractResolvedValue(nameMap);
            String email = extractResolvedValue(emailMap);
            String phone = extractResolvedValue(phoneMap);
    
            if (String.isBlank(role)) {
                throw new IllegalArgumentException('Recipient role is invalid.');
            }
            if (String.isBlank(recipientId)) {
                throw new IllegalArgumentException('Recipient id is missing.');
            }
            if (sequence == null) {
                throw new IllegalArgumentException('Recipient sequence is missing.');
            }
            if (String.isBlank(name)) {
                throw new IllegalArgumentException('Recipient name is required.');
            }
            if (String.isBlank(email) && String.isBlank(phone)) {
                throw new IllegalArgumentException('At least one of recipient email or phone is required.');
            }
    
            if (role == 'signer') {
                hasSigner = true;
            }
    
            if (firstRecipientSequence == null || sequence < firstRecipientSequence) {
                firstRecipientSequence = sequence;
                firstRecipientName = name;
                firstRecipientEmail = email;
                firstRecipientRole = role;
                firstRecipientPhone = phone;
            }
    
            Map<String, Object> apiRecipient = new Map<String, Object>{
                'id' => recipientId,
                'name' => name,
                'role' => role,
                'routing_order' => sequence
            };
    
            if (!String.isBlank(email)) {
                apiRecipient.put('email', email);
            }
    
            if (!String.isBlank(phone)) {
                apiRecipient.put('phone', phone);
                smsConsent = true;
            }
    
            List<String> assignedComponents = assignedComponentsByRecipient.get(recipientId);
            if (assignedComponents != null && !assignedComponents.isEmpty()) {
                apiRecipient.put('assigned_components', assignedComponents);
            }
    
            apiRecipients.add(apiRecipient);
        }
    
        if (!hasSigner) {
            throw new IllegalArgumentException('At least one signer is required.');
        }
    
        Map<String, Object> payload = new Map<String, Object>{
    'template_id' => templateId,
    'document_name' => documentName,
    'routing_type' => 'sequential',
    'delivery_mode' => 'public_recipients',
    'send_email' => false,
    'require_auth' => false,
    'sms_mode' => false,
    'expires_at' => null,
    'from_name' => DOCFLOW_FROM_NAME,
    'from_email' => DOCFLOW_FROM_EMAIL,
    'merge_fields' => mergeFields,
    'recipients' => apiRecipients
};
    
        PayloadBuildResult result = new PayloadBuildResult();
        result.payload = payload;
        result.firstRecipientEmail = firstRecipientEmail;
        result.firstRecipientName = firstRecipientName;
        result.firstRecipientRole = firstRecipientRole;
        result.fromAddressValue = fromAddressValue;
        result.firstRecipientPhone = firstRecipientPhone;
        return result;
    }
    private static void addMergeFieldsFromTemplateMetadata(
    Set<String> selectFields,
    Map<String, Schema.SObjectField> accountFieldMap,
    String templateMetadataJson
) {
    if (String.isBlank(templateMetadataJson)) {
        return;
    }

    Map<String, Object> templateMetadata =
        (Map<String, Object>) JSON.deserializeUntyped(templateMetadataJson);

    if (templateMetadata == null) {
        return;
    }

    List<Object> fields = getTemplateFields(templateMetadata);
    if (fields == null) {
        return;
    }

    for (Object fieldObj : fields) {
        if (!(fieldObj instanceof Map<String, Object>)) {
            continue;
        }

        Map<String, Object> fieldRow = (Map<String, Object>) fieldObj;
        if (!isMergeField(fieldRow)) {
            continue;
        }

        String objectName = extractMergeSourceObjectName(fieldRow);
        String fieldName = extractMergeSourceFieldName(fieldRow);

        if (String.isBlank(objectName) || String.isBlank(fieldName)) {
            continue;
        }

        if (objectName.toLowerCase() != 'account') {
            continue;
        }

        String accountFieldApi = resolveAccountFieldApi(fieldName, accountFieldMap);
        if (!String.isBlank(accountFieldApi)) {
            selectFields.add(accountFieldApi);
        }
    }
}

private static List<Object> getTemplateFields(Map<String, Object> templateMetadata) {
    if (templateMetadata == null) {
        return null;
    }

    if (templateMetadata.get('fields') instanceof List<Object>) {
        return (List<Object>) templateMetadata.get('fields');
    }

    if (templateMetadata.get('field_placements') instanceof List<Object>) {
        return (List<Object>) templateMetadata.get('field_placements');
    }

    return null;
}

private static String extractMergeSourceObjectName(Map<String, Object> fieldRow) {
    if (fieldRow == null) {
        return null;
    }

    Map<String, Object> mergeSource = null;

    if (fieldRow.get('mergeSource') instanceof Map<String, Object>) {
        mergeSource = (Map<String, Object>) fieldRow.get('mergeSource');
    } else if (fieldRow.get('merge_source') instanceof Map<String, Object>) {
        mergeSource = (Map<String, Object>) fieldRow.get('merge_source');
    }

    if (mergeSource == null) {
        return null;
    }

    String objectName = normalizeText(safeString(mergeSource.get('objectName')));
    if (String.isBlank(objectName)) {
        objectName = normalizeText(safeString(mergeSource.get('object')));
    }

    return objectName;
}

private static String extractMergeSourceFieldName(Map<String, Object> fieldRow) {
    if (fieldRow == null) {
        return null;
    }

    Map<String, Object> mergeSource = null;

    if (fieldRow.get('mergeSource') instanceof Map<String, Object>) {
        mergeSource = (Map<String, Object>) fieldRow.get('mergeSource');
    } else if (fieldRow.get('merge_source') instanceof Map<String, Object>) {
        mergeSource = (Map<String, Object>) fieldRow.get('merge_source');
    }

    if (mergeSource == null) {
        return null;
    }

    String fieldName = normalizeText(safeString(mergeSource.get('fieldName')));
    if (String.isBlank(fieldName)) {
        fieldName = normalizeText(safeString(mergeSource.get('field_name')));
    }

    return fieldName;
}

private static Map<String, List<String>> buildTemplateAssignedComponents(Map<String, Object> config) {
    Map<String, List<String>> byRecipient = new Map<String, List<String>>();

    if (config == null) {
        return byRecipient;
    }

    List<Object> fieldAssignments = (List<Object>) config.get('fieldAssignments');
    List<Object> mergeAssignments = (List<Object>) config.get('mergeAssignments');

    addTemplateAssignmentRows(byRecipient, fieldAssignments);
    addTemplateAssignmentRows(byRecipient, mergeAssignments);

    return byRecipient;
}

private static void addTemplateAssignmentRows(
    Map<String, List<String>> byRecipient,
    List<Object> rows
) {
    if (rows == null) {
        return;
    }

    for (Object rowObj : rows) {
        if (!(rowObj instanceof Map<String, Object>)) {
            continue;
        }

        Map<String, Object> row = (Map<String, Object>) rowObj;

        // Merge fields must never go into assigned_components
        if (isMergeField(row)) {
            continue;
        }

        String recipientId = normalizeText(safeString(row.get('recipientId')));
        String fieldId = normalizeText(safeString(row.get('fieldId')));

        if (String.isBlank(recipientId) || String.isBlank(fieldId)) {
            continue;
        }

        if (!byRecipient.containsKey(recipientId)) {
            byRecipient.put(recipientId, new List<String>());
        }

        byRecipient.get(recipientId).add(fieldId);
    }
}

private static Map<String, Object> buildTemplateMergeFields(
    Map<String, Object> templateMetadata,
    Account acc,
    String templateId
) {
    Map<String, Object> mergeFields = new Map<String, Object>();

    if (templateMetadata == null || String.isBlank(templateId)) {
        return mergeFields;
    }

    Map<String, Object> selectedTemplate = resolveSelectedTemplateMetadata(templateMetadata, templateId);
    if (selectedTemplate == null) {
        return mergeFields;
    }

    List<Object> fields = getTemplateFields(selectedTemplate);
    if (fields == null) {
        return mergeFields;
    }

    for (Object fieldObj : fields) {
        if (!(fieldObj instanceof Map<String, Object>)) {
            continue;
        }

        Map<String, Object> fieldRow = (Map<String, Object>) fieldObj;
        if (!isMergeField(fieldRow)) {
            continue;
        }

        String objectName = extractMergeSourceObjectName(fieldRow);
        String fieldName = extractMergeSourceFieldName(fieldRow);

        if (String.isBlank(objectName) || String.isBlank(fieldName)) {
            continue;
        }

        if (objectName.toLowerCase() != 'account') {
            continue;
        }

        String resolvedValue = resolveMergeValue(acc, fieldName);

        if (resolvedValue != null) {
            mergeFields.put('Account.' + fieldName, resolvedValue);
        }
    }

    return mergeFields;
}
    private static Map<String, Object> resolveSelectedTemplateMetadata(
    Map<String, Object> templateMetadata,
    String templateId
) {
    if (templateMetadata == null || String.isBlank(templateId)) {
        return null;
    }

    // Case 1: already a single selected template object
    String directTemplateId = normalizeText(firstNonBlank(
        safeString(templateMetadata.get('templateId')),
        safeString(templateMetadata.get('template_id'))
    ));

    if (!String.isBlank(directTemplateId) && directTemplateId == templateId) {
        return templateMetadata;
    }

    // Case 2: wrapped API response with data[]
    if (templateMetadata.get('data') instanceof List<Object>) {
        List<Object> rows = (List<Object>) templateMetadata.get('data');

        for (Object rowObj : rows) {
            if (!(rowObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) rowObj;
            String rowTemplateId = normalizeText(firstNonBlank(
                safeString(row.get('templateId')),
                safeString(row.get('template_id'))
            ));

            if (!String.isBlank(rowTemplateId) && rowTemplateId == templateId) {
                return row;
            }
        }
    }

    return null;
}
    private static String firstNonBlank(String value1, String value2) {
    return !String.isBlank(value1) ? value1 : value2;
}

    private static Account queryAccountForDoc(Doc_Flow_Document__c doc) {
        if (doc == null || doc.Account__c == null) {
            return null;
        }
    
        Map<String, Schema.SObjectField> accountFieldMap = Schema.SObjectType.Account.fields.getMap();
        Set<String> selectFields = new Set<String>{ 'Id', 'PersonContactId' };
    
        addFieldIfPresent(selectFields, accountFieldMap, 'BillingStreet');
        addFieldIfPresent(selectFields, accountFieldMap, 'BillingCity');
        addFieldIfPresent(selectFields, accountFieldMap, 'BillingState');
        addFieldIfPresent(selectFields, accountFieldMap, 'BillingPostalCode');
    
        addFieldIfPresent(selectFields, accountFieldMap, 'PersonMailingStreet');
        addFieldIfPresent(selectFields, accountFieldMap, 'PersonMailingCity');
        addFieldIfPresent(selectFields, accountFieldMap, 'PersonMailingState');
        addFieldIfPresent(selectFields, accountFieldMap, 'PersonMailingPostalCode');
    
        String sourceType = normalizeSourceType(safeString(doc.get(DOC_SOURCE_TYPE_FIELD)));
    
        if (isTemplateSource(sourceType)) {
            addMergeFieldsFromTemplateMetadata(selectFields, accountFieldMap, doc.Template_Metadata_Json__c);
        } else {
            addMergeFieldsFromPackageMetadata(selectFields, accountFieldMap, doc.Package_Metadata_Json__c);
        }
    
        List<String> orderedFields = new List<String>();
        orderedFields.addAll(selectFields);
        orderedFields.sort();
    
        Id accountId = doc.Account__c;
        String soql =
            'SELECT ' + String.join(orderedFields, ',') +
            ' FROM Account WHERE Id = :accountId LIMIT 1';
    
        return (Account) Database.query(soql);
    }

    private static void addMergeFieldsFromPackageMetadata(
    Set<String> selectFields,
    Map<String, Schema.SObjectField> accountFieldMap,
    String packageMetadataJson
) {
    if (String.isBlank(packageMetadataJson)) {
        return;
    }

    Map<String, Object> packageMetadata =
        (Map<String, Object>) JSON.deserializeUntyped(packageMetadataJson);

    if (packageMetadata == null) {
        return;
    }

    List<Object> templates = (List<Object>) packageMetadata.get('templates');
    if (templates == null) {
        return;
    }

    for (Object templateObj : templates) {
        if (!(templateObj instanceof Map<String, Object>)) {
            continue;
        }

        Map<String, Object> templateRow = (Map<String, Object>) templateObj;
        List<Object> fields = (List<Object>) templateRow.get('fields');

        if (fields == null) {
            continue;
        }

        for (Object fieldObj : fields) {
            if (!(fieldObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> fieldRow = (Map<String, Object>) fieldObj;
            if (!isMergeField(fieldRow)) {
                continue;
            }

            Map<String, Object> mergeSource = (Map<String, Object>) fieldRow.get('mergeSource');
            if (mergeSource == null) {
                continue;
            }

            String objectName = normalizeText(safeString(mergeSource.get('objectName')));
            String fieldName = normalizeText(safeString(mergeSource.get('fieldName')));

            if (String.isBlank(objectName) || String.isBlank(fieldName)) {
                continue;
            }

            if (objectName.toLowerCase() != 'account') {
                continue;
            }

            String accountFieldApi = resolveAccountFieldApi(fieldName, accountFieldMap);
            if (!String.isBlank(accountFieldApi)) {
                selectFields.add(accountFieldApi);
            }
        }
    }
}
    
    private static void addFieldIfPresent(
    Set<String> selectFields,
    Map<String, Schema.SObjectField> accountFieldMap,
    String fieldApi
) {
    if (selectFields == null || accountFieldMap == null || String.isBlank(fieldApi)) {
        return;
    }

    if (accountFieldMap.containsKey(fieldApi)) {
        selectFields.add(fieldApi);
    }
}

    private static List<Object> buildDynamicFieldAssignments(List<Object> rawAssignments) {
        Map<String, List<Object>> fieldsByTemplate = new Map<String, List<Object>>();

        if (rawAssignments == null) {
            return new List<Object>();
        }

        for (Object rowObj : rawAssignments) {
            if (!(rowObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) rowObj;
            String templateId = normalizeText(safeString(row.get('templateId')));
            String fieldId = normalizeText(safeString(row.get('fieldId')));
            String recipientId = normalizeText(safeString(row.get('recipientId')));

            if (String.isBlank(templateId) || String.isBlank(fieldId) || String.isBlank(recipientId)) {
                continue;
            }

            if (!fieldsByTemplate.containsKey(templateId)) {
                fieldsByTemplate.put(templateId, new List<Object>());
            }

            fieldsByTemplate.get(templateId).add(new Map<String, Object>{
                'field_id' => fieldId,
                'recipient_id' => recipientId
            });
        }

        List<String> templateIds = new List<String>();
        templateIds.addAll(fieldsByTemplate.keySet());
        templateIds.sort();

        List<Object> result = new List<Object>();
        for (String templateId : templateIds) {
            result.add(new Map<String, Object>{
                'template_id' => templateId,
                'fields' => fieldsByTemplate.get(templateId)
            });
        }

        return result;
    }

    private static List<Object> buildDynamicTemplateMergeFields(
        Map<String, Object> packageMetadata,
        Account acc
    ) {
        List<Object> result = new List<Object>();

        if (packageMetadata == null) {
            return result;
        }

        List<Object> templates = (List<Object>) packageMetadata.get('templates');
        if (templates == null) {
            return result;
        }

        for (Object templateObj : templates) {
            if (!(templateObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> templateRow = (Map<String, Object>) templateObj;
            String templateId = normalizeText(safeString(templateRow.get('templateId')));
            if (String.isBlank(templateId)) {
                continue;
            }

            Map<String, Object> mergeFields = new Map<String, Object>();
            List<Object> fields = (List<Object>) templateRow.get('fields');

            if (fields != null) {
                for (Object fieldObj : fields) {
                    if (!(fieldObj instanceof Map<String, Object>)) {
                        continue;
                    }

                    Map<String, Object> fieldRow = (Map<String, Object>) fieldObj;
                    if (!isMergeField(fieldRow)) {
                        continue;
                    }

                    Map<String, Object> mergeSource = (Map<String, Object>) fieldRow.get('mergeSource');
                    if (mergeSource == null) {
                        continue;
                    }

                    String objectName = normalizeText(safeString(mergeSource.get('objectName')));
                    String fieldName = normalizeText(safeString(mergeSource.get('fieldName')));

                    if (String.isBlank(objectName) || String.isBlank(fieldName)) {
                        continue;
                    }

                    if (objectName.toLowerCase() != 'account') {
                        continue;
                    }

                    mergeFields.put(
                        objectName + '.' + fieldName,
                        resolveMergeValue(acc, fieldName)
                    );
                }
            }

            if (!mergeFields.isEmpty()) {
                result.add(new Map<String, Object>{
                    'template_id' => templateId,
                    'merge_fields' => mergeFields
                });
            }
        }

        return result;
    }

    private static String resolveMergeValue(Account acc, String fieldName) {
    if (acc == null || String.isBlank(fieldName)) {
        return null;
    }

    Map<String, Schema.SObjectField> accountFieldMap = Schema.SObjectType.Account.fields.getMap();
    String accountFieldApi = resolveAccountFieldApi(fieldName, accountFieldMap);

    if (String.isBlank(accountFieldApi) || !accountFieldMap.containsKey(accountFieldApi)) {
        return null;
    }

    Object value;

    try {
        value = acc.get(accountFieldApi);
    } catch (Exception ex) {
        return null;
    }

    if (value == null) {
        return null;
    }

    Schema.DisplayType fieldType = accountFieldMap.get(accountFieldApi).getDescribe().getType();

    if (fieldType == Schema.DisplayType.Date) {
        return formatDateForUs((Date) value);
    }

    if (fieldType == Schema.DisplayType.DateTime) {
        return formatDateForUs(((Datetime) value).date());
    }

    return normalizeText(String.valueOf(value));
}
    
    private static String formatDateOnly(Date d) {
    if (d == null) {
        return null;
    }

    Datetime dt = Datetime.newInstanceGmt(d.year(), d.month(), d.day(), 0, 0, 0);
    return dt.formatGmt('yyyy-MM-dd');
}
    
    private static String formatDateForUs(Date value) {
    if (value == null) {
        return null;
    }

    String monthValue = value.month() < 10
        ? '0' + String.valueOf(value.month())
        : String.valueOf(value.month());

    String dayValue = value.day() < 10
        ? '0' + String.valueOf(value.day())
        : String.valueOf(value.day());

    return monthValue + '/' + dayValue + '/' + String.valueOf(value.year());
}

private static String buildFormattedAddress(Account acc, String sourceFieldName) {
    if (acc == null) {
        return null;
    }

    Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Account.fields.getMap();

    String street;
    String city;
    String state;
    String postalCode;

    if (sourceFieldName == 'personmailingaddress' || sourceFieldName == 'personmailingstreet') {
        street = fieldMap.containsKey('PersonMailingStreet') ? safeString(acc.get('PersonMailingStreet')) : null;
        city = fieldMap.containsKey('PersonMailingCity') ? safeString(acc.get('PersonMailingCity')) : null;
        state = fieldMap.containsKey('PersonMailingState') ? safeString(acc.get('PersonMailingState')) : null;
        postalCode = fieldMap.containsKey('PersonMailingPostalCode') ? safeString(acc.get('PersonMailingPostalCode')) : null;

        if (String.isBlank(street) && String.isBlank(city) && String.isBlank(state) && String.isBlank(postalCode)) {
            street = fieldMap.containsKey('BillingStreet') ? safeString(acc.get('BillingStreet')) : null;
            city = fieldMap.containsKey('BillingCity') ? safeString(acc.get('BillingCity')) : null;
            state = fieldMap.containsKey('BillingState') ? safeString(acc.get('BillingState')) : null;
            postalCode = fieldMap.containsKey('BillingPostalCode') ? safeString(acc.get('BillingPostalCode')) : null;
        }
    } else {
        street = fieldMap.containsKey('BillingStreet') ? safeString(acc.get('BillingStreet')) : null;
        city = fieldMap.containsKey('BillingCity') ? safeString(acc.get('BillingCity')) : null;
        state = fieldMap.containsKey('BillingState') ? safeString(acc.get('BillingState')) : null;
        postalCode = fieldMap.containsKey('BillingPostalCode') ? safeString(acc.get('BillingPostalCode')) : null;
    }

    List<String> parts = new List<String>();

    if (!String.isBlank(street)) {
        parts.add(street.trim());
    }
    if (!String.isBlank(city)) {
        parts.add(city.trim());
    }
    if (!String.isBlank(state)) {
        parts.add(state.trim());
    }
    if (!String.isBlank(postalCode)) {
        parts.add(postalCode.trim());
    }

    return parts.isEmpty() ? null : String.join(parts, ', ');
}

    private static String resolveAccountFieldApi(
        String sourceFieldName,
        Map<String, Schema.SObjectField> accountFieldMap
    ) {
        if (String.isBlank(sourceFieldName)) {
            return null;
        }

        String lowerName = sourceFieldName.trim().toLowerCase();

        if (lowerName == 'personmailingaddress') {
    return 'PersonMailingStreet';
}

if (lowerName == 'personmailingstreet') {
    if (accountFieldMap.containsKey('PersonMailingStreet')) return 'PersonMailingStreet';
    if (accountFieldMap.containsKey('BillingStreet')) return 'BillingStreet';
}

if (lowerName == 'billingaddress') {
    return 'BillingStreet';
}

        if (lowerName == 'personmailingcity') {
            if (accountFieldMap.containsKey('PersonMailingCity')) return 'PersonMailingCity';
            if (accountFieldMap.containsKey('BillingCity')) return 'BillingCity';
        }

        if (lowerName == 'personmailingstate') {
            if (accountFieldMap.containsKey('PersonMailingState')) return 'PersonMailingState';
            if (accountFieldMap.containsKey('BillingState')) return 'BillingState';
        }

        if (lowerName == 'personmailingpostalcode') {
            if (accountFieldMap.containsKey('PersonMailingPostalCode')) return 'PersonMailingPostalCode';
            if (accountFieldMap.containsKey('BillingPostalCode')) return 'BillingPostalCode';
        }

        for (String fieldApi : accountFieldMap.keySet()) {
            if (fieldApi.toLowerCase() == lowerName) {
                return fieldApi;
            }
        }

        return null;
    }

    private static Boolean isMergeField(Map<String, Object> fieldRow) {
    if (fieldRow == null) {
        return false;
    }

    // If merge source exists, it is definitely a merge field
    if (fieldRow.get('mergeSource') instanceof Map<String, Object>) {
        return true;
    }
    if (fieldRow.get('merge_source') instanceof Map<String, Object>) {
        return true;
    }

    // If field type says merge, trust that
    String fieldType = safeString(fieldRow.get('fieldType'));
    if (String.isBlank(fieldType)) {
        fieldType = safeString(fieldRow.get('field_type'));
    }
    if (String.isBlank(fieldType)) {
        fieldType = safeString(fieldRow.get('type'));
    }

    if (!String.isBlank(fieldType) && fieldType.trim().toLowerCase() == 'merge') {
        return true;
    }

    // Fallback to explicit booleans only if type/source did not tell us
    if (fieldRow.containsKey('isMerge') && fieldRow.get('isMerge') != null) {
        return normalizeBoolean(fieldRow.get('isMerge'));
    }

    if (fieldRow.containsKey('is_merge') && fieldRow.get('is_merge') != null) {
        return normalizeBoolean(fieldRow.get('is_merge'));
    }

    return false;
}

    private static void mapSuccessFields(
        Doc_Flow_Document__c upd,
        Map<String, Object> root
    ) {
        if (root == null) {
            return;
        }
    
        if (root.containsKey('document_id')) {
            String documentId = safeString(root.get('document_id'));
            if (!String.isBlank(documentId)) {
                upd.Document_Id__c = documentId;
            }
        }
    
        if (root.containsKey('document_name')) {
            String documentName = safeString(root.get('document_name'));
            if (!String.isBlank(documentName)) {
                upd.Document_Name__c = documentName;
            }
        }
    
        if (!String.isBlank(upd.Document_Id__c) || !String.isBlank(upd.Document_Name__c)) {
            return;
        }
    
        List<Object> documents = (List<Object>) root.get('documents');
        if (documents != null && !documents.isEmpty()) {
            Map<String, Object> firstDocument = (Map<String, Object>) documents[0];
            if (firstDocument != null) {
                if (firstDocument.containsKey('document_id')) {
                    upd.Document_Id__c = safeString(firstDocument.get('document_id'));
                }
                if (firstDocument.containsKey('document_name')) {
                    upd.Document_Name__c = safeString(firstDocument.get('document_name'));
                }
            }
        }
    }

    private static String extractRecipientAccessLink(
    Map<String, Object> root,
    String recipientEmail
) {
    if (root == null) {
        return null;
    }

    List<Object> links = (List<Object>) root.get('recipient_links');
    if (links != null && !links.isEmpty()) {
        if (!String.isBlank(recipientEmail)) {
            for (Object row : links) {
                Map<String, Object> linkRow = (Map<String, Object>) row;
                String email = safeString(linkRow.get('email'));
                if (!String.isBlank(email) && email.toLowerCase() == recipientEmail.toLowerCase()) {
                    return safeString(linkRow.get('access_link'));
                }
            }
        }

        Map<String, Object> first = (Map<String, Object>) links[0];
        return safeString(first.get('access_link'));
    }

    if (root.containsKey('access_link')) {
        return safeString(root.get('access_link'));
    }

    if (root.containsKey('public_link')) {
        return safeString(root.get('public_link'));
    }

    return null;
}

    private static String extractFailureMessage(
        Map<String, Object> root,
        HttpResponse res
    ) {
        if (root != null && root.containsKey('message') && root.get('message') != null) {
            return safeTrim(String.valueOf(root.get('message')), 32000);
        }

        return safeTrim(
            'HTTP ' + res.getStatusCode() + ' - ' + res.getStatus() + ' | ' + res.getBody(),
            32000
        );
    }

    private static String templateForInitialRole(String role) {
        if (role == 'signer') {
            return TEMPLATE_SEND_DEV_NAME;
        }
        if (role == 'approver') {
            return TEMPLATE_APPROVAL_DEV_NAME;
        }
        if (role == 'reviewer') {
            return TEMPLATE_REVIEW_DEV_NAME;
        }

        return null;
    }

    private static void sendInitialEmails(List<InitialEmailWork> workItems) {
        if (workItems.isEmpty()) {
            return;
        }

        Map<String, Id> templateIdsByDevName = getTemplateIdsByDeveloperNames(
            new Set<String>{
                TEMPLATE_SEND_DEV_NAME,
                TEMPLATE_APPROVAL_DEV_NAME,
                TEMPLATE_REVIEW_DEV_NAME
            }
        );

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<InitialEmailWork> sendOrder = new List<InitialEmailWork>();
        List<Doc_Flow_Document__c> immediateErrors = new List<Doc_Flow_Document__c>();

        for (InitialEmailWork work : workItems) {
            if (work == null || work.docId == null) {
                continue;
            }

            if (String.isBlank(work.templateDeveloperName)) {
                immediateErrors.add(new Doc_Flow_Document__c(
                    Id = work.docId,
                    Error_Message__c = 'Initial email not sent: template developer name was blank.'
                ));
                continue;
            }

            if (String.isBlank(work.toEmail)) {
                immediateErrors.add(new Doc_Flow_Document__c(
                    Id = work.docId,
                    Error_Message__c = 'Initial email not sent: recipient email was blank.'
                ));
                continue;
            }

            if (work.targetContactId == null) {
                immediateErrors.add(new Doc_Flow_Document__c(
                    Id = work.docId,
                    Error_Message__c = 'Initial email not sent: target contact id was blank.'
                ));
                continue;
            }

            Id templateId = templateIdsByDevName.get(work.templateDeveloperName);
            if (templateId == null) {
                immediateErrors.add(new Doc_Flow_Document__c(
                    Id = work.docId,
                    Error_Message__c =
                        'Initial email not sent: template not found for developer name ' +
                        work.templateDeveloperName + '.'
                ));
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTemplateId(templateId);
            mail.setTargetObjectId(work.targetContactId);
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

        if (!immediateErrors.isEmpty()) {
            Database.update(immediateErrors, false);
        }

        if (emails.isEmpty()) {
            return;
        }

        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

            List<Doc_Flow_Document__c> sendFailures = new List<Doc_Flow_Document__c>();

            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    InitialEmailWork failedWork = sendOrder[i];

                    sendFailures.add(new Doc_Flow_Document__c(
                        Id = failedWork.docId,
                        Error_Message__c = buildEmailSendErrorMessage(
                            failedWork.templateDeveloperName,
                            failedWork.toEmail,
                            results[i]
                        )
                    ));
                }
            }

            if (!sendFailures.isEmpty()) {
                Database.update(sendFailures, false);
            }

        } catch (Exception ex) {
            List<Doc_Flow_Document__c> fatalSendErrors = new List<Doc_Flow_Document__c>();

            for (InitialEmailWork work : sendOrder) {
                fatalSendErrors.add(new Doc_Flow_Document__c(
                    Id = work.docId,
                    Error_Message__c = safeTrim(
                        'Initial email send failed with exception: ' + ex.getMessage(),
                        32000
                    )
                ));
            }

            if (!fatalSendErrors.isEmpty()) {
                Database.update(fatalSendErrors, false);
            }
        }
    }

    private static String buildEmailSendErrorMessage(
        String templateDeveloperName,
        String toEmail,
        Messaging.SendEmailResult result
    ) {
        String message =
            'Initial email send failed. ' +
            'Template=' + templateDeveloperName +
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

    private static String normalizeRoleForApi(String role) {
        if (String.isBlank(role)) {
            return null;
        }

        String v = role.trim().toLowerCase();
        if (v == 'signer') return 'signer';
        if (v == 'approver') return 'approver';
        if (v == 'reviewer') return 'reviewer';
        if (v == 'receive_copy' || v == 'receive copy') return 'receive_copy';
        return null;
    }

    private static String extractResolvedValue(Map<String, Object> section) {
        if (section == null) {
            return null;
        }
        return normalizeText(safeString(section.get('resolvedValue')));
    }

    private static Boolean normalizeBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return 'true' == String.valueOf(value).toLowerCase();
    }

    private static String normalizeText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static Integer normalizeInteger(Object value) {
        if (value == null) return null;
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Long) return Integer.valueOf(String.valueOf(value));
        if (value instanceof Decimal) return ((Decimal) value).intValue();
        return Integer.valueOf(String.valueOf(value));
    }

    private static String getStringValue(SObject sobj, String fieldApi) {
        if (sobj == null || String.isBlank(fieldApi)) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = sobj.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldApi)) {
            return null;
        }

        Object val = sobj.get(fieldApi);
        return val == null ? null : String.valueOf(val);
    }

    private static void putIfFieldExists(SObject sobj, String fieldApi, Object value) {
        Map<String, Schema.SObjectField> fieldMap = sobj.getSObjectType().getDescribe().fields.getMap();
        if (fieldMap.containsKey(fieldApi)) {
            sobj.put(fieldApi, value);
        }
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String safeTrim(String input, Integer maxLen) {
        if (input == null) {
            return null;
        }
        if (input.length() <= maxLen) {
            return input;
        }
        return input.substring(0, maxLen);
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