public with sharing class DocFlowQuickActionController {

    private static final String DOC_RECIPIENT_CONFIG_JSON_FIELD = 'Recipient_Config_Json__c';
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

    public class InitResponse {
        @AuraEnabled public List<FieldOption> nameOptions { get; set; }
        @AuraEnabled public List<FieldOption> emailOptions { get; set; }
        @AuraEnabled public List<FieldOption> phoneOptions { get; set; }

        @AuraEnabled public String defaultMemberNameFieldApi { get; set; }
        @AuraEnabled public String defaultMemberEmailFieldApi { get; set; }
        @AuraEnabled public String defaultMemberPhoneFieldApi { get; set; }

        @AuraEnabled public List<FromAddressOption> fromAddressOptions { get; set; }
        @AuraEnabled public String defaultFromAddressValue { get; set; }

        public InitResponse() {
            nameOptions = new List<FieldOption>();
            emailOptions = new List<FieldOption>();
            phoneOptions = new List<FieldOption>();
            fromAddressOptions = new List<FromAddressOption>();
        }
    }

    @AuraEnabled(cacheable=true)
    public static InitResponse getRecipientInitData(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        Account acc = [
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

        response.defaultMemberNameFieldApi =
            fieldExists(fieldMap, 'Name') ? 'Name' : null;
        response.defaultMemberEmailFieldApi =
            fieldExists(fieldMap, 'PersonEmail') ? 'PersonEmail' : null;
        response.defaultMemberPhoneFieldApi =
            fieldExists(fieldMap, 'PersonMobilePhone') ? 'PersonMobilePhone' : null;

        response.fromAddressOptions = buildFromAddressOptions();
        response.defaultFromAddressValue =
            response.fromAddressOptions.isEmpty() ? null : response.fromAddressOptions[0].value;

        return response;
    }

    @AuraEnabled
    public static Id createDocFlowDocumentWithConfig(Id accountId, String templateId, String configJson) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        if (String.isBlank(templateId)) {
            throw new AuraHandledException('Template Id is required.');
        }

        if (String.isBlank(configJson)) {
            throw new AuraHandledException('Recipient configuration is required.');
        }

        ensureDocCreatePermissions();

        Map<String, Object> rawConfig;
        try {
            rawConfig = (Map<String, Object>) JSON.deserializeUntyped(configJson);
        } catch (Exception ex) {
            throw new AuraHandledException('Recipient configuration JSON is invalid.');
        }

        if (rawConfig == null) {
            throw new AuraHandledException('Recipient configuration is invalid.');
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

        FromAddressOption selectedFromAddress = fromAddressMap.get(fromAddressValue);

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

        List<Object> cleanedRecipients = new List<Object>();
        Integer seq = 1;

        for (Object row : recipientsRaw) {
            Map<String, Object> recipientRaw = (Map<String, Object>) row;

            String typeVal = normalizeRecipientType(safeString(recipientRaw.get('type')));
            String roleVal = normalizeRole(safeString(recipientRaw.get('role')));

            if (String.isBlank(typeVal)) {
                throw new AuraHandledException('Recipient type must be Member or Surrogate.');
            }

            if (String.isBlank(roleVal)) {
                throw new AuraHandledException('Recipient role is invalid.');
            }

            Map<String, Object> nameRaw = (Map<String, Object>) recipientRaw.get('name');
            Map<String, Object> emailRaw = (Map<String, Object>) recipientRaw.get('email');
            Map<String, Object> phoneRaw = (Map<String, Object>) recipientRaw.get('phone');

            Map<String, Object> cleanedName =
                resolveFieldConfig(acc, accountFieldMap, nameRaw, 'name', true, seq);

            Map<String, Object> cleanedEmail =
                resolveFieldConfig(acc, accountFieldMap, emailRaw, 'email', true, seq);

            Map<String, Object> cleanedPhone =
                resolveFieldConfig(acc, accountFieldMap, phoneRaw, 'phone', false, seq);

            cleanedRecipients.add(new Map<String, Object>{
                'sequence' => seq,
                'routingOrder' => seq,
                'type' => typeVal,
                'role' => roleVal,
                'name' => cleanedName,
                'email' => cleanedEmail,
                'phone' => cleanedPhone
            });

            seq++;
        }

        Map<String, Object> finalConfig = new Map<String, Object>{
            'version' => '2.0',
            'fromAddress' => new Map<String, Object>{
                'value' => selectedFromAddress.value,
                'name' => selectedFromAddress.label,
                'email' => selectedFromAddress.email,
                'source' => selectedFromAddress.source
            },
            'recipients' => cleanedRecipients
        };

        String storedJson = JSON.serialize(finalConfig);
        if (storedJson.length() > 32768) {
            throw new AuraHandledException('Recipient configuration is too large to store.');
        }

        Doc_Flow_Document__c docRecord = new Doc_Flow_Document__c();
        docRecord.Account__c = acc.Id;
        docRecord.Salesforce_Org_Id__c = UserInfo.getOrganizationId();
        docRecord.Source_Object__c = 'Account';
        docRecord.Source_Record_Id__c = String.valueOf(acc.Id);
        docRecord.Status__c = 'initiated';
        docRecord.Template_Id__c = templateId;
        docRecord.put(DOC_RECIPIENT_CONFIG_JSON_FIELD, storedJson);

        insert docRecord;
        return docRecord.Id;
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
        DOC_RECIPIENT_CONFIG_JSON_FIELD
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

    private static String normalizeRecipientType(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String v = value.trim().toLowerCase();
        if (v == 'member') return 'Member';
        if (v == 'surrogate') return 'Surrogate';
        return null;
    }

    private static String normalizeRole(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String v = value.trim().toLowerCase();
        if (v == 'signer') return 'signer';
        if (v == 'approver') return 'approver';
        if (v == 'reviewer') return 'reviewer';
        if (v == 'receive_copy' || v == 'receive copy') return 'receive_copy';
        return null;
    }

    private static String normalizeMode(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String v = value.trim().toLowerCase();
        if (v == 'field') return 'field';
        if (v == 'manual') return 'manual';
        return null;
    }

    private static String normalizeText(String value) {
        return String.isBlank(value) ? null : value.trim();
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
}