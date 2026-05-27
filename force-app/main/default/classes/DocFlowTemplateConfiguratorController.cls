public with sharing class DocFlowTemplateConfiguratorController {

    private static final String BASE_URL = 'https://api.cluvik.com';
    private static final String API_KEY = 'dfk_AeSCS10hxyricKBkgudeuCyW5y09MRN8gaNcpCGzIOI';

    private static final String DOC_RECIPIENT_CONFIG_JSON_FIELD = 'Recipient_Config_Json__c';
    private static final String DOC_TEMPLATE_METADATA_JSON_FIELD = 'Template_Metadata_Json__c';
    private static final String DOC_SOURCE_TYPE_FIELD = 'DocFlow_Source_Type__c';

    private static final Integer MAX_RECIPIENTS = 5;

    public class FieldOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }

        public FieldOption() {}
        public FieldOption(String label, String apiName) {
            this.label = label;
            this.apiName = apiName;
        }
    }

    public class FromAddressOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String source { get; set; }

        public FromAddressOption() {}
        public FromAddressOption(String label, String email, String value, String source) {
            this.label = label;
            this.email = email;
            this.value = value;
            this.source = source;
        }
    }

    public class MergeSourceInfo {
        @AuraEnabled public String objectName { get; set; }
        @AuraEnabled public String fieldName { get; set; }
    }

    public class TemplateFieldInfo {
        @AuraEnabled public String fieldId { get; set; }
        @AuraEnabled public String fieldName { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public Boolean isMerge { get; set; }
        @AuraEnabled public MergeSourceInfo mergeSource { get; set; }
    }

    public class TemplateInfo {
        @AuraEnabled public String templateId { get; set; }
        @AuraEnabled public String templateName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String createdAt { get; set; }
        @AuraEnabled public Integer templateVersion { get; set; }
        @AuraEnabled public Boolean isLatestVersion { get; set; }
        @AuraEnabled public List<TemplateFieldInfo> fields { get; set; }

        public TemplateInfo() {
            fields = new List<TemplateFieldInfo>();
        }
    }

    public class InitResponse {
        @AuraEnabled public List<FieldOption> nameOptions { get; set; }
        @AuraEnabled public List<FieldOption> emailOptions { get; set; }
        @AuraEnabled public List<FieldOption> phoneOptions { get; set; }

        @AuraEnabled public String defaultNameFieldApi { get; set; }
        @AuraEnabled public String defaultEmailFieldApi { get; set; }
        @AuraEnabled public String defaultPhoneFieldApi { get; set; }

        @AuraEnabled public List<FromAddressOption> fromAddressOptions { get; set; }
        @AuraEnabled public String defaultFromAddressValue { get; set; }

        @AuraEnabled public List<TemplateInfo> templates { get; set; }

        public InitResponse() {
            nameOptions = new List<FieldOption>();
            emailOptions = new List<FieldOption>();
            phoneOptions = new List<FieldOption>();
            fromAddressOptions = new List<FromAddressOption>();
            templates = new List<TemplateInfo>();
        }
    }

    @AuraEnabled
    public static InitResponse getTemplateConfiguratorInitData(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

       Account accountCheck = [
    SELECT Id
    FROM Account
    WHERE Id = :accountId
    LIMIT 1
];

        InitResponse response = new InitResponse();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Account.fields.getMap();

        for (String fieldApi : fieldMap.keySet()) {
            Schema.DescribeFieldResult d = fieldMap.get(fieldApi).getDescribe();
            if (!d.isAccessible() || d.isCalculated()) {
                continue;
            }

            if (isSelectableNameField(d, fieldApi)) {
                response.nameOptions.add(new FieldOption(d.getLabel(), fieldApi));
            } else if (isSelectableEmailField(d)) {
                response.emailOptions.add(new FieldOption(d.getLabel(), fieldApi));
            } else if (isSelectablePhoneField(d)) {
                response.phoneOptions.add(new FieldOption(d.getLabel(), fieldApi));
            }
        }

        response.defaultNameFieldApi = fieldExists(fieldMap, 'Name') ? 'Name' : null;
        response.defaultEmailFieldApi = fieldExists(fieldMap, 'PersonEmail') ? 'PersonEmail' : null;
        response.defaultPhoneFieldApi = fieldExists(fieldMap, 'PersonMobilePhone') ? 'PersonMobilePhone' : null;

        response.fromAddressOptions = buildFromAddressOptions();
response.defaultFromAddressValue = getPreferredFromAddressValue(
    response.fromAddressOptions,
    'support@batoncare.com'
);

        response.templates = fetchTemplates();

        return response;
    }
    
    private static String getPreferredFromAddressValue(
    List<FromAddressOption> options,
    String preferredEmail
) {
    if (options == null || options.isEmpty()) {
        return null;
    }

    for (FromAddressOption item : options) {
        if (item != null &&
            !String.isBlank(item.email) &&
            item.email.trim().toLowerCase() == preferredEmail.toLowerCase()) {
            return item.value;
        }
    }

    return options[0].value;
}

    @AuraEnabled
    public static Id createDocFlowTemplateDraft(
        Id accountId,
        String templateId,
        String templateName,
        String templateMetadataJson,
        String draftConfigJson
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }
        if (String.isBlank(templateId)) {
            throw new AuraHandledException('Template Id is required.');
        }
        if (String.isBlank(templateMetadataJson)) {
            throw new AuraHandledException('Template metadata is required.');
        }
        if (String.isBlank(draftConfigJson)) {
            throw new AuraHandledException('Draft configuration is required.');
        }

        ensureDocCreatePermissions();

        Map<String, Object> templateMetadata;
        Map<String, Object> rawConfig;

        try {
            templateMetadata = (Map<String, Object>) JSON.deserializeUntyped(templateMetadataJson);
        } catch (Exception ex) {
            throw new AuraHandledException('Template metadata JSON is invalid.');
        }

        try {
            rawConfig = (Map<String, Object>) JSON.deserializeUntyped(draftConfigJson);
        } catch (Exception ex) {
            throw new AuraHandledException('Draft configuration JSON is invalid.');
        }

        if (templateMetadata == null || rawConfig == null) {
            throw new AuraHandledException('Template draft data is invalid.');
        }

        String selectedTemplateId = normalizeText(safeString(rawConfig.get('templateId')));
        if (String.isBlank(selectedTemplateId) || selectedTemplateId != templateId) {
            throw new AuraHandledException('Selected template mismatch.');
        }

        Map<String, Object> fromAddressRaw = (Map<String, Object>) rawConfig.get('fromAddress');
        if (fromAddressRaw == null) {
            throw new AuraHandledException('From address is required.');
        }

        String fromAddressValue = normalizeText(safeString(fromAddressRaw.get('value')));
        Map<String, FromAddressOption> fromAddressMap = buildFromAddressOptionMap();
        if (String.isBlank(fromAddressValue) || !fromAddressMap.containsKey(fromAddressValue)) {
            throw new AuraHandledException('Selected from address is invalid.');
        }

        List<Object> recipientsRaw = (List<Object>) rawConfig.get('recipients');
        if (recipientsRaw == null || recipientsRaw.isEmpty()) {
            throw new AuraHandledException('At least one recipient is required.');
        }
        if (recipientsRaw.size() > MAX_RECIPIENTS) {
            throw new AuraHandledException('You can add up to 5 recipients only.');
        }

        Map<String, Schema.SObjectField> accountFieldMap = Schema.SObjectType.Account.fields.getMap();
        Set<String> accountQueryFields = new Set<String>{ 'Id' };

        for (Object row : recipientsRaw) {
            if (!(row instanceof Map<String, Object>)) {
                throw new AuraHandledException('Recipient row is invalid.');
            }

            Map<String, Object> recipientRaw = (Map<String, Object>) row;
            collectFieldApi(accountQueryFields, accountFieldMap, recipientRaw, 'name', 'name');
            collectFieldApi(accountQueryFields, accountFieldMap, recipientRaw, 'email', 'email');
            collectFieldApi(accountQueryFields, accountFieldMap, recipientRaw, 'phone', 'phone');
        }

        List<String> selectFields = new List<String>();
        selectFields.addAll(accountQueryFields);
        selectFields.sort();

        String soql =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM Account WHERE Id = :accountId LIMIT 1';

        Account acc = (Account) Database.query(soql);

        Map<String, Object> templateMetaByFieldKey = indexTemplateFields(templateMetadata);

        List<Object> cleanedRecipients = new List<Object>();
        Set<String> allowedRecipientIds = new Set<String>();
        Integer signerCount = 0;

        for (Object row : recipientsRaw) {
            Map<String, Object> recipientRaw = (Map<String, Object>) row;

            String recipientId = normalizeText(safeString(recipientRaw.get('recipientId')));
            String roleVal = normalizeRole(safeString(recipientRaw.get('role')));
            Integer sequence = normalizeInteger(recipientRaw.get('sequence'));

            if (String.isBlank(recipientId)) {
                throw new AuraHandledException('Recipient id is required.');
            }
            if (allowedRecipientIds.contains(recipientId)) {
                throw new AuraHandledException('Recipient ids must be unique.');
            }
            if (String.isBlank(roleVal)) {
                throw new AuraHandledException('Recipient role is invalid.');
            }

            Map<String, Object> nameRaw = (Map<String, Object>) recipientRaw.get('name');
            Map<String, Object> emailRaw = (Map<String, Object>) recipientRaw.get('email');
            Map<String, Object> phoneRaw = (Map<String, Object>) recipientRaw.get('phone');

            Map<String, Object> cleanedName =
                resolveFieldConfig(acc, accountFieldMap, nameRaw, 'name', true, sequence);

            Map<String, Object> cleanedEmail =
                resolveFieldConfig(acc, accountFieldMap, emailRaw, 'email', false, sequence);

            Map<String, Object> cleanedPhone =
                resolveFieldConfig(acc, accountFieldMap, phoneRaw, 'phone', false, sequence);

            String emailResolved = cleanedEmail == null ? null : safeString(cleanedEmail.get('resolvedValue'));
            String phoneResolved = cleanedPhone == null ? null : safeString(cleanedPhone.get('resolvedValue'));

            if (String.isBlank(emailResolved) && String.isBlank(phoneResolved)) {
                throw new AuraHandledException(
                    'At least one of email or phone is required for recipient ' + String.valueOf(sequence) + '.'
                );
            }

            cleanedRecipients.add(new Map<String, Object>{
                'recipientId' => recipientId,
                'sequence' => sequence,
                'role' => roleVal,
                'name' => cleanedName,
                'email' => cleanedEmail,
                'phone' => cleanedPhone
            });

            allowedRecipientIds.add(recipientId);
            if (roleVal == 'signer') {
                signerCount++;
            }
        }

        if (signerCount == 0) {
            throw new AuraHandledException('At least one signer is required.');
        }

        Map<String, Object> reminderSettingsRaw = (Map<String, Object>) rawConfig.get('reminderSettings');

        Boolean reminderEnabled = reminderSettingsRaw == null
            ? true
            : normalizeBoolean(reminderSettingsRaw.get('enabled'));

        Integer reminderIntervalDays = reminderSettingsRaw == null
            ? 1
            : normalizeInteger(reminderSettingsRaw.get('intervalDays'));

        Integer reminderMaxCount = reminderSettingsRaw == null
            ? 3
            : normalizeInteger(reminderSettingsRaw.get('maxReminders'));

        if (reminderIntervalDays == null || reminderIntervalDays < 1 || reminderIntervalDays > 30) {
            throw new AuraHandledException('Reminder interval must be between 1 and 30 days.');
        }

        if (reminderMaxCount == null || reminderMaxCount < 0 || reminderMaxCount > 20) {
            throw new AuraHandledException('Maximum reminders must be between 0 and 20.');
        }

        List<Object> fieldAssignmentsRaw = (List<Object>) rawConfig.get('fieldAssignments');
        if (fieldAssignmentsRaw == null) {
            fieldAssignmentsRaw = new List<Object>();
        }

        List<Object> mergeAssignmentsRaw = (List<Object>) rawConfig.get('mergeAssignments');
        if (mergeAssignmentsRaw == null) {
            mergeAssignmentsRaw = new List<Object>();
        }

        List<Object> cleanedAssignments = new List<Object>();
        List<Object> cleanedMergeAssignments = new List<Object>();

        for (Object row : fieldAssignmentsRaw) {
            if (!(row instanceof Map<String, Object>)) {
                throw new AuraHandledException('Field assignment row is invalid.');
            }

            Map<String, Object> assignmentRaw = (Map<String, Object>) row;
            String fieldId = normalizeText(safeString(assignmentRaw.get('fieldId')));
            String recipientId = normalizeText(safeString(assignmentRaw.get('recipientId')));

            if (String.isBlank(fieldId)) {
                throw new AuraHandledException('Field assignment requires fieldId.');
            }
            if (String.isBlank(recipientId) || !allowedRecipientIds.contains(recipientId)) {
                throw new AuraHandledException('Field assignment recipient is invalid.');
            }

            if (!templateMetaByFieldKey.containsKey(fieldId)) {
                throw new AuraHandledException('Field assignment does not belong to selected template.');
            }

            Map<String, Object> fieldMeta = (Map<String, Object>) templateMetaByFieldKey.get(fieldId);
            Boolean isMerge = (Boolean) fieldMeta.get('isMerge');

            if (isMerge == true) {
                throw new AuraHandledException('Merge field rows must be passed in mergeAssignments.');
            }

            cleanedAssignments.add(new Map<String, Object>{
                'fieldId' => fieldId,
                'fieldName' => safeString(fieldMeta.get('fieldName')),
                'fieldType' => safeString(fieldMeta.get('fieldType')),
                'required' => fieldMeta.get('required'),
                'recipientId' => recipientId,
                'isMerge' => false
            });
        }

        for (Object row : mergeAssignmentsRaw) {
            if (!(row instanceof Map<String, Object>)) {
                throw new AuraHandledException('Merge assignment row is invalid.');
            }

            Map<String, Object> assignmentRaw = (Map<String, Object>) row;
            String fieldId = normalizeText(safeString(assignmentRaw.get('fieldId')));
            String recipientId = normalizeText(safeString(assignmentRaw.get('recipientId')));

            if (String.isBlank(fieldId)) {
                throw new AuraHandledException('Merge assignment requires fieldId.');
            }
            if (String.isBlank(recipientId) || !allowedRecipientIds.contains(recipientId)) {
                throw new AuraHandledException('Merge assignment recipient is invalid.');
            }

            if (!templateMetaByFieldKey.containsKey(fieldId)) {
                throw new AuraHandledException('Merge assignment does not belong to selected template.');
            }

            Map<String, Object> fieldMeta = (Map<String, Object>) templateMetaByFieldKey.get(fieldId);
            Boolean isMerge = (Boolean) fieldMeta.get('isMerge');

            if (isMerge != true) {
                throw new AuraHandledException('Only merge fields can be passed in mergeAssignments.');
            }

            cleanedMergeAssignments.add(new Map<String, Object>{
                'fieldId' => fieldId,
                'fieldName' => safeString(fieldMeta.get('fieldName')),
                'fieldType' => safeString(fieldMeta.get('fieldType')),
                'required' => fieldMeta.get('required'),
                'recipientId' => recipientId,
                'isMerge' => true,
                'mergeSource' => fieldMeta.get('mergeSource')
            });
        }

        Map<String, Object> finalConfig = new Map<String, Object>{
            'version' => '4.0',
            'sourceType' => 'template',
            'templateId' => templateId,
            'templateName' => String.isBlank(templateName) ? selectedTemplateId : templateName,
            'fromAddress' => new Map<String, Object>{
                'value' => fromAddressMap.get(fromAddressValue).value,
                'name' => fromAddressMap.get(fromAddressValue).label,
                'email' => fromAddressMap.get(fromAddressValue).email,
                'source' => fromAddressMap.get(fromAddressValue).source
            },
            'reminderSettings' => new Map<String, Object>{
                'enabled' => reminderEnabled,
                'intervalDays' => reminderIntervalDays,
                'maxReminders' => reminderMaxCount
            },
            'recipients' => cleanedRecipients,
            'fieldAssignments' => cleanedAssignments,
            'mergeAssignments' => cleanedMergeAssignments
        };

        String storedConfigJson = JSON.serialize(finalConfig);

        String templateDisplayName = normalizeText(safeString(rawConfig.get('documentName')));
        if (String.isBlank(templateDisplayName)) {
            templateDisplayName = String.isBlank(templateName) ? 'DocFlow Template' : templateName;
        }

        Doc_Flow_Document__c draftDoc = new Doc_Flow_Document__c();

        putIfFieldExists(draftDoc, 'Account__c', accountId);
        putIfFieldExists(draftDoc, 'Source_Object__c', 'Account');
        putIfFieldExists(draftDoc, 'Source_Record_Id__c', String.valueOf(accountId));
        putIfFieldExists(draftDoc, 'Salesforce_Org_Id__c', UserInfo.getOrganizationId());
        putIfFieldExists(draftDoc, 'Template_Id__c', templateId);
        putIfFieldExists(draftDoc, 'Document_Name__c', templateDisplayName);
        putIfFieldExists(draftDoc, 'Status__c', 'initiated');
        putIfFieldExists(draftDoc, DOC_RECIPIENT_CONFIG_JSON_FIELD, storedConfigJson);
        putIfFieldExists(draftDoc, DOC_TEMPLATE_METADATA_JSON_FIELD, JSON.serialize(templateMetadata));
        putIfFieldExists(draftDoc, DOC_SOURCE_TYPE_FIELD, 'Template');

        insert draftDoc;
        return draftDoc.Id;
    }

    private static List<TemplateInfo> fetchTemplates() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/api/docflow/public/templates');
        req.setMethod('GET');
        req.setHeader('X-API-Key', API_KEY);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception ex) {
            throw new AuraHandledException('Template fetch failed: ' + ex.getMessage());
        }

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException(
                'Template fetch failed. HTTP ' + res.getStatusCode() + ' - ' + res.getStatus()
            );
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(res.getBody());
        } catch (Exception ex) {
            throw new AuraHandledException('Template response JSON is invalid.');
        }

        List<Object> rawTemplates = new List<Object>();

        if (parsed instanceof List<Object>) {
            rawTemplates = (List<Object>) parsed;
        } else if (parsed instanceof Map<String, Object>) {
            Map<String, Object> root = (Map<String, Object>) parsed;
            if (root.get('templates') instanceof List<Object>) {
                rawTemplates = (List<Object>) root.get('templates');
            } else if (root.get('data') instanceof List<Object>) {
                rawTemplates = (List<Object>) root.get('data');
            } else if (root.get('items') instanceof List<Object>) {
                rawTemplates = (List<Object>) root.get('items');
            }
        }

        List<TemplateInfo> templates = new List<TemplateInfo>();

        for (Object rowObj : rawTemplates) {
            if (!(rowObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) rowObj;

            TemplateInfo template = new TemplateInfo();
            template.templateId = firstNonBlank(
                normalizeText(safeString(row.get('template_id'))),
                normalizeText(safeString(row.get('templateId')))
            );
            template.templateName = firstNonBlank(
                normalizeText(safeString(row.get('template_name'))),
                normalizeText(safeString(row.get('templateName'))),
                normalizeText(safeString(row.get('document_name')))
            );
            template.status = normalizeText(safeString(row.get('status')));
            template.createdAt = normalizeText(safeString(row.get('created_at')));
            template.templateVersion = normalizeInteger(
    row.containsKey('version')
        ? row.get('version')
        : (row.containsKey('template_version') ? row.get('template_version') : row.get('templateVersion'))
);
            template.isLatestVersion = normalizeBoolean(
                row.containsKey('is_latest_version') ? row.get('is_latest_version') : row.get('isLatestVersion')
            );

            List<Object> placements = null;
            if (row.get('field_placements') instanceof List<Object>) {
                placements = (List<Object>) row.get('field_placements');
            } else if (row.get('fields') instanceof List<Object>) {
                placements = (List<Object>) row.get('fields');
            }

            if (placements != null) {
                for (Object fieldObj : placements) {
                    if (!(fieldObj instanceof Map<String, Object>)) {
                        continue;
                    }

                    Map<String, Object> fieldRow = (Map<String, Object>) fieldObj;
                    TemplateFieldInfo fieldInfo = new TemplateFieldInfo();

fieldInfo.fieldId = firstNonBlank(
    normalizeText(safeString(fieldRow.get('field_id'))),
    normalizeText(safeString(fieldRow.get('fieldId'))),
    normalizeText(safeString(fieldRow.get('id')))
);
fieldInfo.fieldName = firstNonBlank(
    normalizeText(safeString(fieldRow.get('field_name'))),
    normalizeText(safeString(fieldRow.get('fieldName'))),
    normalizeText(safeString(fieldRow.get('name')))
);
fieldInfo.fieldType = firstNonBlank(
    normalizeText(safeString(fieldRow.get('field_type'))),
    normalizeText(safeString(fieldRow.get('fieldType'))),
    normalizeText(safeString(fieldRow.get('type')))
);
                    fieldInfo.required = normalizeBoolean(fieldRow.get('required'));
                    fieldInfo.isMerge = isMergeField(fieldRow);

                    Object mergeSourceObj = fieldRow.get('merge_source');
                    if (!(mergeSourceObj instanceof Map<String, Object>)) {
                        mergeSourceObj = fieldRow.get('mergeSource');
                    }

                    if (mergeSourceObj instanceof Map<String, Object>) {
                        Map<String, Object> mergeSourceRow = (Map<String, Object>) mergeSourceObj;
                        MergeSourceInfo mergeSource = new MergeSourceInfo();
                        mergeSource.objectName = firstNonBlank(
                            normalizeText(safeString(mergeSourceRow.get('object'))),
                            normalizeText(safeString(mergeSourceRow.get('objectName')))
                        );
                        mergeSource.fieldName = firstNonBlank(
                            normalizeText(safeString(mergeSourceRow.get('field_name'))),
                            normalizeText(safeString(mergeSourceRow.get('fieldName')))
                        );
                        fieldInfo.mergeSource = mergeSource;
                    }

                    if (!String.isBlank(fieldInfo.fieldId)) {
                        template.fields.add(fieldInfo);
                    }
                }
            }

            if (!String.isBlank(template.templateId)) {
                templates.add(template);
            }
        }

        templates.sort(new TemplateInfoSorter());
        return templates;
    }

    private class TemplateInfoSorter implements Comparator<TemplateInfo> {
        public Integer compare(TemplateInfo a, TemplateInfo b) {
            String aName = a == null ? '' : blankToEmpty(a.templateName).toLowerCase();
            String bName = b == null ? '' : blankToEmpty(b.templateName).toLowerCase();
            return aName.compareTo(bName);
        }
    }

    private static Map<String, Object> indexTemplateFields(Map<String, Object> templateMetadata) {
        Map<String, Object> result = new Map<String, Object>();
        if (templateMetadata == null) {
            return result;
        }

        List<Object> placements = null;
        if (templateMetadata.get('field_placements') instanceof List<Object>) {
            placements = (List<Object>) templateMetadata.get('field_placements');
        } else if (templateMetadata.get('fields') instanceof List<Object>) {
            placements = (List<Object>) templateMetadata.get('fields');
        }

        if (placements == null) {
            return result;
        }

        for (Object fieldObj : placements) {
            if (!(fieldObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> fieldRow = (Map<String, Object>) fieldObj;
            String fieldId = firstNonBlank(
    normalizeText(safeString(fieldRow.get('field_id'))),
    normalizeText(safeString(fieldRow.get('fieldId'))),
    normalizeText(safeString(fieldRow.get('id')))
);

            if (String.isBlank(fieldId)) {
                continue;
            }

            result.put(fieldId, new Map<String, Object>{
                'fieldId' => fieldId,
                'fieldName' => firstNonBlank(
    normalizeText(safeString(fieldRow.get('field_name'))),
    normalizeText(safeString(fieldRow.get('fieldName'))),
    normalizeText(safeString(fieldRow.get('name')))
),
'fieldType' => firstNonBlank(
    normalizeText(safeString(fieldRow.get('field_type'))),
    normalizeText(safeString(fieldRow.get('fieldType'))),
    normalizeText(safeString(fieldRow.get('type')))
),
                'required' => normalizeBoolean(fieldRow.get('required')),
                'isMerge' => isMergeField(fieldRow),
                'mergeSource' => extractMergeSource(fieldRow)
            });
        }

        return result;
    }

    private static Map<String, Object> extractMergeSource(Map<String, Object> fieldRow) {
        if (fieldRow == null) {
            return null;
        }

        Object mergeSourceObj = fieldRow.get('merge_source');
        if (!(mergeSourceObj instanceof Map<String, Object>)) {
            mergeSourceObj = fieldRow.get('mergeSource');
        }

        if (!(mergeSourceObj instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> mergeSourceRow = (Map<String, Object>) mergeSourceObj;
        return new Map<String, Object>{
            'objectName' => firstNonBlank(
                normalizeText(safeString(mergeSourceRow.get('object'))),
                normalizeText(safeString(mergeSourceRow.get('objectName')))
            ),
            'fieldName' => firstNonBlank(
                normalizeText(safeString(mergeSourceRow.get('field_name'))),
                normalizeText(safeString(mergeSourceRow.get('fieldName')))
            )
        };
    }

    private static Boolean isMergeField(Map<String, Object> fieldRow) {
        if (fieldRow == null) {
            return false;
        }

        if (fieldRow.containsKey('is_merge') && fieldRow.get('is_merge') != null) {
            return normalizeBoolean(fieldRow.get('is_merge'));
        }

        if (fieldRow.containsKey('isMerge') && fieldRow.get('isMerge') != null) {
            return normalizeBoolean(fieldRow.get('isMerge'));
        }

        String fieldType = firstNonBlank(
            normalizeText(safeString(fieldRow.get('field_type'))),
            normalizeText(safeString(fieldRow.get('fieldType')))
        );

        return !String.isBlank(fieldType) && fieldType.toLowerCase() == 'merge';
    }

    private static void collectFieldApi(
        Set<String> queryFields,
        Map<String, Schema.SObjectField> fieldMap,
        Map<String, Object> recipientRaw,
        String key,
        String labelForError
    ) {
        Map<String, Object> section = (Map<String, Object>) recipientRaw.get(key);
        if (section == null) {
            return;
        }

        String mode = normalizeText(safeString(section.get('mode')));
        if (mode != 'field') {
            return;
        }

        String fieldApi = normalizeText(safeString(section.get('fieldApi')));
        if (String.isBlank(fieldApi)) {
            throw new AuraHandledException('Recipient ' + labelForError + ' field is required.');
        }

        if (!fieldMap.containsKey(fieldApi)) {
            throw new AuraHandledException('Field ' + fieldApi + ' does not exist on Account.');
        }

        queryFields.add(fieldApi);
    }

    private static Map<String, Object> resolveFieldConfig(
        Account acc,
        Map<String, Schema.SObjectField> fieldMap,
        Map<String, Object> rawSection,
        String labelForError,
        Boolean required,
        Integer sequence
    ) {
        if (rawSection == null) {
            if (required) {
                throw new AuraHandledException('Recipient ' + String.valueOf(sequence) + ' ' + labelForError + ' is required.');
            }
            return new Map<String, Object>{
                'mode' => 'manual',
                'fieldApi' => null,
                'resolvedValue' => null
            };
        }

        String mode = normalizeText(safeString(rawSection.get('mode')));
        if (String.isBlank(mode)) {
            mode = 'manual';
        }

        if (mode == 'field') {
            String fieldApi = normalizeText(safeString(rawSection.get('fieldApi')));
            if (String.isBlank(fieldApi)) {
                throw new AuraHandledException('Recipient ' + String.valueOf(sequence) + ' ' + labelForError + ' field is required.');
            }
            if (!fieldMap.containsKey(fieldApi)) {
                throw new AuraHandledException('Field ' + fieldApi + ' does not exist on Account.');
            }

            Object fieldValue = acc.get(fieldApi);
            String resolvedValue = fieldValue == null ? null : String.valueOf(fieldValue);

            if (required && String.isBlank(resolvedValue)) {
                throw new AuraHandledException(
                    'Recipient ' + String.valueOf(sequence) + ' ' + labelForError +
                    ' field ' + fieldApi + ' resolved to blank.'
                );
            }

            return new Map<String, Object>{
                'mode' => 'field',
                'fieldApi' => fieldApi,
                'resolvedValue' => resolvedValue
            };
        }

        String manualValue = normalizeText(safeString(rawSection.get('manualValue')));
        if (required && String.isBlank(manualValue)) {
            throw new AuraHandledException('Recipient ' + String.valueOf(sequence) + ' ' + labelForError + ' is required.');
        }

        return new Map<String, Object>{
            'mode' => 'manual',
            'fieldApi' => null,
            'resolvedValue' => manualValue
        };
    }

    private static List<FromAddressOption> buildFromAddressOptions() {
        List<FromAddressOption> result = new List<FromAddressOption>();

        result.add(new FromAddressOption(
            UserInfo.getName(),
            UserInfo.getUserEmail(),
            'USER:' + UserInfo.getUserId(),
            'USER'
        ));

        for (OrgWideEmailAddress owea : [
            SELECT Id, Address, DisplayName
            FROM OrgWideEmailAddress
            ORDER BY Address
        ]) {
            result.add(new FromAddressOption(
                String.isBlank(owea.DisplayName) ? owea.Address : owea.DisplayName,
                owea.Address,
                'OWEA:' + owea.Id,
                'OWEA'
            ));
        }

        return result;
    }

    private static Map<String, FromAddressOption> buildFromAddressOptionMap() {
        Map<String, FromAddressOption> result = new Map<String, FromAddressOption>();
        for (FromAddressOption item : buildFromAddressOptions()) {
            result.put(item.value, item);
        }
        return result;
    }

    private static Boolean isSelectableNameField(Schema.DescribeFieldResult d, String fieldApi) {
        String typeName = String.valueOf(d.getType());
        return typeName == 'STRING' && (
            fieldApi.toLowerCase().contains('name') ||
            d.getLabel().toLowerCase().contains('name')
        );
    }

    private static Boolean isSelectableEmailField(Schema.DescribeFieldResult d) {
        return String.valueOf(d.getType()) == 'EMAIL';
    }

    private static Boolean isSelectablePhoneField(Schema.DescribeFieldResult d) {
        String typeName = String.valueOf(d.getType());
        return typeName == 'PHONE';
    }

    private static Boolean fieldExists(Map<String, Schema.SObjectField> fieldMap, String apiName) {
        return fieldMap != null && fieldMap.containsKey(apiName);
    }

    private static String normalizeRole(String role) {
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

    private static String firstNonBlank(String value1, String value2) {
        return !String.isBlank(value1) ? value1 : value2;
    }

    private static String firstNonBlank(String value1, String value2, String value3) {
        if (!String.isBlank(value1)) return value1;
        if (!String.isBlank(value2)) return value2;
        return value3;
    }

    private static Integer normalizeInteger(Object value) {
        if (value == null) return null;
        if (value instanceof Integer) return (Integer) value;
        if (value instanceof Long) return Integer.valueOf(String.valueOf(value));
        if (value instanceof Decimal) return ((Decimal) value).intValue();
        return Integer.valueOf(String.valueOf(value));
    }

    private static Boolean normalizeBoolean(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return (Boolean) value;
        return 'true' == String.valueOf(value).toLowerCase();
    }

    private static String normalizeText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    private static void putIfFieldExists(SObject sobj, String fieldApi, Object value) {
        if (sobj == null || String.isBlank(fieldApi)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = sobj.getSObjectType().getDescribe().fields.getMap();
        if (fieldMap.containsKey(fieldApi)) {
            sobj.put(fieldApi, value);
        }
    }

    private static void ensureDocCreatePermissions() {
        if (!Schema.sObjectType.Doc_Flow_Document__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create Doc Flow Documents.');
        }
    }
}