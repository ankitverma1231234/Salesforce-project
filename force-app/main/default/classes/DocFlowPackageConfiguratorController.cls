public with sharing class DocFlowPackageConfiguratorController {

    private static final String BASE_URL = 'https://api.cluvik.com';
    private static final String API_KEY = 'dfk_AeSCS10hxyricKBkgudeuCyW5y09MRN8gaNcpCGzIOI';

    private static final String DOC_RECIPIENT_CONFIG_JSON_FIELD = 'Recipient_Config_Json__c';
    private static final String DOC_PACKAGE_METADATA_JSON_FIELD = 'Package_Metadata_Json__c';
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

    public class PackageFieldInfo {
        @AuraEnabled public String fieldId { get; set; }
        @AuraEnabled public String fieldName { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public Boolean isMerge { get; set; }
        @AuraEnabled public MergeSourceInfo mergeSource { get; set; }
    }

    public class PackageTemplateInfo {
        @AuraEnabled public String templateId { get; set; }
        @AuraEnabled public String documentName { get; set; }
        @AuraEnabled public String templateName { get; set; }
        @AuraEnabled public Integer sortOrder { get; set; }
        @AuraEnabled public Integer templateVersion { get; set; }
        @AuraEnabled public Boolean isLatestVersion { get; set; }
        @AuraEnabled public List<PackageFieldInfo> fields { get; set; }

        public PackageTemplateInfo() {
            fields = new List<PackageFieldInfo>();
        }
    }

    public class PackageInfo {
        @AuraEnabled public String packageId { get; set; }
        @AuraEnabled public String packageName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String createdAt { get; set; }
        @AuraEnabled public List<PackageTemplateInfo> templates { get; set; }

        public PackageInfo() {
            templates = new List<PackageTemplateInfo>();
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

        @AuraEnabled public List<PackageInfo> packages { get; set; }

        public InitResponse() {
            nameOptions = new List<FieldOption>();
            emailOptions = new List<FieldOption>();
            phoneOptions = new List<FieldOption>();
            fromAddressOptions = new List<FromAddressOption>();
            packages = new List<PackageInfo>();
        }
    }

    @AuraEnabled
    public static InitResponse getConfiguratorInitData(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        Account accCheck = [
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
        response.defaultFromAddressValue =
            response.fromAddressOptions.isEmpty() ? null : response.fromAddressOptions[0].value;

        response.packages = fetchPackages();
        return response;
    }

    @AuraEnabled
    public static Id createDocFlowPackageDraft(
        Id accountId,
        String packageId,
        String packageName,
        String packageMetadataJson,
        String draftConfigJson
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }
        if (String.isBlank(packageId)) {
            throw new AuraHandledException('Package Id is required.');
        }
        if (String.isBlank(packageMetadataJson)) {
            throw new AuraHandledException('Package metadata is required.');
        }
        if (String.isBlank(draftConfigJson)) {
            throw new AuraHandledException('Draft configuration is required.');
        }

        ensureDocCreatePermissions();

        Map<String, Object> packageMetadata;
        Map<String, Object> rawConfig;

        try {
            packageMetadata = (Map<String, Object>) JSON.deserializeUntyped(packageMetadataJson);
        } catch (Exception ex) {
            throw new AuraHandledException('Package metadata JSON is invalid.');
        }

        try {
            rawConfig = (Map<String, Object>) JSON.deserializeUntyped(draftConfigJson);
        } catch (Exception ex) {
            throw new AuraHandledException('Draft configuration JSON is invalid.');
        }

        if (packageMetadata == null) {
            throw new AuraHandledException('Package metadata is invalid.');
        }
        if (rawConfig == null) {
            throw new AuraHandledException('Draft configuration is invalid.');
        }

        String selectedPackageId = normalizeText(safeString(rawConfig.get('packageId')));
        if (String.isBlank(selectedPackageId) || selectedPackageId != packageId) {
            throw new AuraHandledException('Selected package mismatch.');
        }

        Map<String, Object> fromAddressRaw = (Map<String, Object>) rawConfig.get('fromAddress');
        if (fromAddressRaw == null) {
            throw new AuraHandledException('From address is required.');
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

        Map<String, Object> packageMetaByFieldKey = indexPackageFields(packageMetadata);

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
                    'Recipient ' + sequence + ': at least one of email or phone is required.'
                );
            }

            if (roleVal == 'signer') {
                signerCount++;
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
    String templateId = normalizeText(safeString(assignmentRaw.get('templateId')));
    String fieldId = normalizeText(safeString(assignmentRaw.get('fieldId')));
    String recipientId = normalizeText(safeString(assignmentRaw.get('recipientId')));

    if (String.isBlank(templateId) || String.isBlank(fieldId)) {
        throw new AuraHandledException('Field assignment requires templateId and fieldId.');
    }
    if (String.isBlank(recipientId) || !allowedRecipientIds.contains(recipientId)) {
        throw new AuraHandledException('Field assignment recipient is invalid.');
    }

    String metaKey = templateId + '::' + fieldId;
    if (!packageMetaByFieldKey.containsKey(metaKey)) {
        throw new AuraHandledException('Field assignment does not belong to selected package.');
    }

    Map<String, Object> packageFieldMeta = (Map<String, Object>) packageMetaByFieldKey.get(metaKey);
    Boolean isMerge = (Boolean) packageFieldMeta.get('isMerge');

    if (isMerge == true) {
        throw new AuraHandledException('Merge field rows must be passed in mergeAssignments.');
    }

    cleanedAssignments.add(new Map<String, Object>{
        'templateId' => templateId,
        'documentName' => safeString(packageFieldMeta.get('documentName')),
        'fieldId' => fieldId,
        'fieldName' => safeString(packageFieldMeta.get('fieldName')),
        'fieldType' => safeString(packageFieldMeta.get('fieldType')),
        'required' => packageFieldMeta.get('required'),
        'recipientId' => recipientId,
        'isMerge' => false
    });
}

for (Object row : mergeAssignmentsRaw) {
    if (!(row instanceof Map<String, Object>)) {
        throw new AuraHandledException('Merge assignment row is invalid.');
    }

    Map<String, Object> assignmentRaw = (Map<String, Object>) row;
    String templateId = normalizeText(safeString(assignmentRaw.get('templateId')));
    String fieldId = normalizeText(safeString(assignmentRaw.get('fieldId')));
    String recipientId = normalizeText(safeString(assignmentRaw.get('recipientId')));

    if (String.isBlank(templateId) || String.isBlank(fieldId)) {
        throw new AuraHandledException('Merge assignment requires templateId and fieldId.');
    }
    if (String.isBlank(recipientId) || !allowedRecipientIds.contains(recipientId)) {
        throw new AuraHandledException('Merge assignment recipient is invalid.');
    }

    String metaKey = templateId + '::' + fieldId;
    if (!packageMetaByFieldKey.containsKey(metaKey)) {
        throw new AuraHandledException('Merge assignment does not belong to selected package.');
    }

    Map<String, Object> packageFieldMeta = (Map<String, Object>) packageMetaByFieldKey.get(metaKey);
    Boolean isMerge = (Boolean) packageFieldMeta.get('isMerge');

    if (isMerge != true) {
        throw new AuraHandledException('Only merge fields can be passed in mergeAssignments.');
    }

    cleanedMergeAssignments.add(new Map<String, Object>{
        'templateId' => templateId,
        'documentName' => safeString(packageFieldMeta.get('documentName')),
        'fieldId' => fieldId,
        'fieldName' => safeString(packageFieldMeta.get('fieldName')),
        'fieldType' => safeString(packageFieldMeta.get('fieldType')),
        'required' => packageFieldMeta.get('required'),
        'recipientId' => recipientId,
        'isMerge' => true,
        'mergeSource' => packageFieldMeta.get('mergeSource')
    });
}

Map<String, Object> finalConfig = new Map<String, Object>{
    'version' => '3.1',
    'sourceType' => 'package',
    'packageId' => packageId,
    'packageName' => String.isBlank(packageName) ? selectedPackageId : packageName,
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
        if (storedConfigJson.length() > 32768) {
            throw new AuraHandledException('Recipient configuration is too large to store.');
        }

        String storedPackageJson = JSON.serialize(packageMetadata);
        if (storedPackageJson.length() > 32768) {
            throw new AuraHandledException('Package metadata is too large to store.');
        }

        Doc_Flow_Document__c docRecord = new Doc_Flow_Document__c();
        docRecord.Account__c = acc.Id;
        docRecord.Salesforce_Org_Id__c = UserInfo.getOrganizationId();
        docRecord.Source_Object__c = 'Account';
        docRecord.Source_Record_Id__c = String.valueOf(acc.Id);
        docRecord.Status__c = 'initiated';
        docRecord.Template_Id__c = packageId;
        docRecord.put(DOC_SOURCE_TYPE_FIELD, 'Package');

        docRecord.put(DOC_RECIPIENT_CONFIG_JSON_FIELD, storedConfigJson);
        putRequiredPackageMetadata(docRecord, storedPackageJson);

        insert docRecord;
        return docRecord.Id;
    }

    private static void ensureDocCreatePermissions() {
        if (Test.isRunningTest()) {
            return;
        }

        if (!Schema.sObjectType.Doc_Flow_Document__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create Doc Flow Document records.');
        }

        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Doc_Flow_Document__c.fields.getMap();

        List<String> requiredFields = new List<String>{
            'Account__c',
            'Salesforce_Org_Id__c',
            'Source_Object__c',
            'Source_Record_Id__c',
            'Status__c',
            'Template_Id__c',
            DOC_RECIPIENT_CONFIG_JSON_FIELD,
            DOC_PACKAGE_METADATA_JSON_FIELD,
            DOC_SOURCE_TYPE_FIELD
        };

        List<String> blockedFields = new List<String>();
        for (String fieldApi : requiredFields) {
            if (!fieldMap.containsKey(fieldApi) || !fieldMap.get(fieldApi).getDescribe().isCreateable()) {
                blockedFields.add(fieldApi);
            }
        }

        if (!blockedFields.isEmpty()) {
            throw new AuraHandledException(
                'You do not have permission to populate these fields: ' + String.join(blockedFields, ', ')
            );
        }
    }

    private static void putRequiredPackageMetadata(SObject sobj, String value) {
        Map<String, Schema.SObjectField> fieldMap = sobj.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey(DOC_PACKAGE_METADATA_JSON_FIELD)) {
            throw new AuraHandledException('Package_Metadata_Json__c field is missing on Doc_Flow_Document__c.');
        }
        sobj.put(DOC_PACKAGE_METADATA_JSON_FIELD, value);
    }

    private static Map<String, Object> indexPackageFields(Map<String, Object> packageMetadata) {
    Map<String, Object> result = new Map<String, Object>();

    List<Object> templates = (List<Object>) packageMetadata.get('templates');
    if (templates == null) {
        return result;
    }

    for (Object tplObj : templates) {
        if (!(tplObj instanceof Map<String, Object>)) {
            continue;
        }

        Map<String, Object> tpl = (Map<String, Object>) tplObj;
        String templateId = safeString(tpl.get('templateId'));
        String documentName = safeString(tpl.get('documentName'));
        List<Object> fields = (List<Object>) tpl.get('fields');

        if (fields == null) {
            continue;
        }

        for (Object fieldObj : fields) {
            if (!(fieldObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> fld = (Map<String, Object>) fieldObj;
            String fieldId = safeString(fld.get('fieldId'));
            if (String.isBlank(templateId) || String.isBlank(fieldId)) {
                continue;
            }

            result.put(
                templateId + '::' + fieldId,
                new Map<String, Object>{
                    'templateId' => templateId,
                    'documentName' => documentName,
                    'fieldId' => fieldId,
                    'fieldName' => safeString(fld.get('fieldName')),
                    'fieldType' => safeString(fld.get('fieldType')),
                    'required' => fld.get('required'),
                    'isMerge' => fld.get('isMerge'),
                    'mergeSource' => fld.get('mergeSource')
                }
            );
        }
    }

    return result;
}

    private static void collectFieldApi(
        Set<String> queryFields,
        Map<String, Schema.SObjectField> fieldMap,
        Map<String, Object> recipientRaw,
        String sectionName,
        String expectedType
    ) {
        if (recipientRaw == null || !recipientRaw.containsKey(sectionName)) {
            return;
        }

        Object rawSection = recipientRaw.get(sectionName);
        if (!(rawSection instanceof Map<String, Object>)) {
            return;
        }

        Map<String, Object> section = (Map<String, Object>) rawSection;
        String mode = normalizeMode(safeString(section.get('mode')));
        String fieldApi = normalizeText(safeString(section.get('fieldApi')));

        if (mode == 'field' && !String.isBlank(fieldApi)) {
            validateFieldApi(fieldMap, fieldApi, expectedType);
            queryFields.add(fieldApi);
        }
    }

    private static Map<String, Object> resolveFieldConfig(
        Account acc,
        Map<String, Schema.SObjectField> fieldMap,
        Map<String, Object> rawConfig,
        String expectedType,
        Boolean required,
        Integer recipientIndex
    ) {
        if (rawConfig == null) {
            if (required) {
                throw new AuraHandledException('Recipient ' + recipientIndex + ': ' + capitalize(expectedType) + ' is required.');
            }
            return new Map<String, Object>{
                'mode' => 'manual',
                'fieldApi' => null,
                'resolvedValue' => null
            };
        }

        String mode = normalizeMode(safeString(rawConfig.get('mode')));
        if (String.isBlank(mode)) {
            throw new AuraHandledException(
                'Recipient ' + recipientIndex + ': ' + capitalize(expectedType) + ' mode is invalid.'
            );
        }

        if (mode == 'field') {
            String fieldApi = normalizeText(safeString(rawConfig.get('fieldApi')));
            if (String.isBlank(fieldApi)) {
                if (required) {
                    throw new AuraHandledException(
                        'Recipient ' + recipientIndex + ': ' + capitalize(expectedType) + ' field is required.'
                    );
                }
                return new Map<String, Object>{
                    'mode' => 'field',
                    'fieldApi' => null,
                    'resolvedValue' => null
                };
            }

            validateFieldApi(fieldMap, fieldApi, expectedType);
            String resolvedValue = normalizeText(getStringValue(acc, fieldApi));

            if (required && String.isBlank(resolvedValue)) {
                throw new AuraHandledException(
                    'Recipient ' + recipientIndex + ': selected ' + expectedType + ' field value is blank.'
                );
            }

            if (expectedType == 'email' && !String.isBlank(resolvedValue) && !isValidEmail(resolvedValue)) {
                throw new AuraHandledException(
                    'Recipient ' + recipientIndex + ': selected email field value is invalid.'
                );
            }

            if (expectedType == 'phone' && !String.isBlank(resolvedValue)) {
                resolvedValue = normalizePhoneOptional(resolvedValue);
            }

            return new Map<String, Object>{
                'mode' => 'field',
                'fieldApi' => fieldApi,
                'resolvedValue' => resolvedValue
            };
        }

        if (mode == 'manual') {
            String manualValue = normalizeText(safeString(rawConfig.get('manualValue')));

            if (required && String.isBlank(manualValue)) {
                throw new AuraHandledException(
                    'Recipient ' + recipientIndex + ': manual ' + expectedType + ' value is required.'
                );
            }

            if (expectedType == 'email' && !String.isBlank(manualValue) && !isValidEmail(manualValue)) {
                throw new AuraHandledException(
                    'Recipient ' + recipientIndex + ': manual email is invalid.'
                );
            }

            if (expectedType == 'phone' && !String.isBlank(manualValue)) {
                manualValue = normalizePhoneOptional(manualValue);
            }

            return new Map<String, Object>{
                'mode' => 'manual',
                'fieldApi' => null,
                'resolvedValue' => manualValue
            };
        }

        throw new AuraHandledException(
            'Recipient ' + recipientIndex + ': ' + capitalize(expectedType) + ' mode is invalid.'
        );
    }

    private static void validateFieldApi(
        Map<String, Schema.SObjectField> fieldMap,
        String fieldApi,
        String expectedType
    ) {
        if (!fieldMap.containsKey(fieldApi)) {
            throw new AuraHandledException('Selected ' + expectedType + ' field does not exist.');
        }

        Schema.DescribeFieldResult d = fieldMap.get(fieldApi).getDescribe();
        if (!d.isAccessible() || d.isCalculated()) {
            throw new AuraHandledException('Selected ' + expectedType + ' field is not accessible.');
        }

        if (expectedType == 'name' && !isSelectableNameField(d, fieldApi)) {
            throw new AuraHandledException('Recipient name must use a text field.');
        }

        if (expectedType == 'email' && !isSelectableEmailField(d)) {
            throw new AuraHandledException('Recipient email must use an email field.');
        }

        if (expectedType == 'phone' && !isSelectablePhoneField(d)) {
            throw new AuraHandledException('Recipient phone must use a phone field.');
        }
    }

    private static List<FromAddressOption> buildFromAddressOptions() {
        List<FromAddressOption> options = new List<FromAddressOption>();
        Set<String> seenEmails = new Set<String>();

        String currentUserId = UserInfo.getUserId();
        String currentUserName = UserInfo.getName();
        String currentUserEmail = UserInfo.getUserEmail();

        if (!String.isBlank(currentUserEmail)) {
            String normalized = currentUserEmail.trim().toLowerCase();
            seenEmails.add(normalized);

            options.add(
                new FromAddressOption(
                    String.isBlank(currentUserName) ? currentUserEmail : currentUserName,
                    currentUserEmail,
                    'USER:' + currentUserId,
                    'USER'
                )
            );
        }

        for (OrgWideEmailAddress owea : [
            SELECT Id, Address, DisplayName
            FROM OrgWideEmailAddress
            ORDER BY DisplayName, Address
        ]) {
            if (String.isBlank(owea.Address)) {
                continue;
            }

            String normalized = owea.Address.trim().toLowerCase();
            if (seenEmails.contains(normalized)) {
                continue;
            }

            seenEmails.add(normalized);

            options.add(
                new FromAddressOption(
                    String.isBlank(owea.DisplayName) ? owea.Address : owea.DisplayName,
                    owea.Address,
                    'OWEA:' + owea.Id,
                    'OWEA'
                )
            );
        }

        return options;
    }

    private static Map<String, FromAddressOption> buildFromAddressOptionMap() {
        Map<String, FromAddressOption> result = new Map<String, FromAddressOption>();
        for (FromAddressOption option : buildFromAddressOptions()) {
            result.put(option.value, option);
        }
        return result;
    }

    private static List<PackageInfo> fetchPackages() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/api/public/packages');
        req.setMethod('GET');
        req.setHeader('X-API-Key', API_KEY);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException(
                'Unable to load DocFlow packages. HTTP ' + res.getStatusCode() + ' - ' + res.getStatus()
            );
        }

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> packageRows = (List<Object>) root.get('packages');
        List<PackageInfo> packages = new List<PackageInfo>();

        if (packageRows == null) {
            return packages;
        }

        for (Object pkgObj : packageRows) {
            if (!(pkgObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> pkgMap = (Map<String, Object>) pkgObj;
            PackageInfo pkg = new PackageInfo();
            pkg.packageId = safeString(pkgMap.get('package_id'));
            pkg.packageName = safeString(pkgMap.get('package_name'));
            pkg.status = safeString(pkgMap.get('status'));
            pkg.createdAt = safeString(pkgMap.get('created_at'));

            List<Object> templatesRaw = (List<Object>) pkgMap.get('templates');
            if (templatesRaw != null) {
                for (Object tplObj : templatesRaw) {
                    if (!(tplObj instanceof Map<String, Object>)) {
                        continue;
                    }

                    Map<String, Object> tplMap = (Map<String, Object>) tplObj;
                    PackageTemplateInfo tpl = new PackageTemplateInfo();
                    tpl.templateId = safeString(tplMap.get('template_id'));
                    tpl.documentName = safeString(tplMap.get('document_name'));
                    tpl.templateName = safeString(tplMap.get('template_name'));
                    tpl.sortOrder = normalizeInteger(tplMap.get('order'));
                    tpl.templateVersion = normalizeInteger(tplMap.get('template_version'));
                    tpl.isLatestVersion = normalizeBoolean(tplMap.get('is_latest_version'));

                    List<Object> fieldsRaw = (List<Object>) tplMap.get('fields');
                    if (fieldsRaw != null) {
                        for (Object fieldObj : fieldsRaw) {
                            if (!(fieldObj instanceof Map<String, Object>)) {
                                continue;
                            }

                            Map<String, Object> fldMap = (Map<String, Object>) fieldObj;
                            PackageFieldInfo fld = new PackageFieldInfo();
                            fld.fieldId = safeString(fldMap.get('field_id'));
                            fld.fieldName = safeString(fldMap.get('field_name'));
                            fld.fieldType = safeString(fldMap.get('field_type'));
                            fld.required = normalizeBoolean(fldMap.get('required'));
                            fld.isMerge = 'merge' == fld.fieldType;

                            if (fldMap.containsKey('merge_source') && fldMap.get('merge_source') instanceof Map<String, Object>) {
                                Map<String, Object> mergeRaw = (Map<String, Object>) fldMap.get('merge_source');
                                MergeSourceInfo mergeInfo = new MergeSourceInfo();
                                mergeInfo.objectName = safeString(mergeRaw.get('object'));
                                mergeInfo.fieldName = safeString(mergeRaw.get('field_name'));
                                fld.mergeSource = mergeInfo;
                            }

                            tpl.fields.add(fld);
                        }
                    }

                    pkg.templates.add(tpl);
                }
            }

            packages.add(pkg);
        }

        return packages;
    }

    private static Boolean fieldExists(Map<String, Schema.SObjectField> fieldMap, String fieldApi) {
        return fieldMap.containsKey(fieldApi) && fieldMap.get(fieldApi).getDescribe().isAccessible();
    }

    private static Boolean isSelectableNameField(Schema.DescribeFieldResult d, String fieldApi) {
        if (d == null || String.isBlank(fieldApi)) {
            return false;
        }
        if (fieldApi == 'Name') {
            return true;
        }
        return d.getType() == Schema.DisplayType.String;
    }

    private static Boolean isSelectableEmailField(Schema.DescribeFieldResult d) {
        return d != null && d.getType() == Schema.DisplayType.Email;
    }

    private static Boolean isSelectablePhoneField(Schema.DescribeFieldResult d) {
        return d != null && d.getType() == Schema.DisplayType.Phone;
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

    private static String normalizeRole(String value) {
        if (String.isBlank(value)) return null;

        String v = value.trim().toLowerCase();
        if (v == 'signer') return 'signer';
        if (v == 'approver') return 'approver';
        if (v == 'reviewer') return 'reviewer';
        if (v == 'receive_copy' || v == 'receive copy') return 'receive_copy';
        return null;
    }

    private static String normalizeMode(String value) {
        if (String.isBlank(value)) return null;

        String v = value.trim().toLowerCase();
        if (v == 'field') return 'field';
        if (v == 'manual') return 'manual';
        return null;
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

    private static Boolean normalizeBoolean(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean) return (Boolean) value;
        return 'true' == String.valueOf(value).toLowerCase();
    }

    private static Boolean isValidEmail(String value) {
        if (String.isBlank(value)) {
            return false;
        }

        String email = value.trim();
        Pattern p = Pattern.compile('^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$');
        Matcher m = p.matcher(email);
        return m.matches();
    }

    private static String normalizePhoneOptional(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String phone = value.trim();
        Boolean hasLeadingPlus = phone.startsWith('+');

        phone = phone.replaceAll('[\\s\\-\\(\\)\\.]+', '');

        if (hasLeadingPlus) {
            phone = '+' + phone.substring(1).replaceAll('[^0-9]', '');
        } else {
            phone = phone.replaceAll('[^0-9]', '');
        }

        String digitsOnly = hasLeadingPlus ? phone.substring(1) : phone;

        if (String.isBlank(digitsOnly) || !Pattern.matches('^[0-9]+$', digitsOnly)) {
            throw new AuraHandledException('Recipient phone is invalid.');
        }

        if (digitsOnly.length() < 7 || digitsOnly.length() > 15) {
            throw new AuraHandledException('Recipient phone must contain between 7 and 15 digits.');
        }

        return hasLeadingPlus ? '+' + digitsOnly : digitsOnly;
    }

    private static String safeString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String capitalize(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.substring(0, 1).toUpperCase() + value.substring(1);
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

}