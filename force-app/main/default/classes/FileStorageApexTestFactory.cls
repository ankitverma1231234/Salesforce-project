@IsTest(SeeAllData=true)
public class FileStorageApexTestFactory {
    public static Account getTestAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Metriport_Patient_Id__c = 'patient-123'
            LIMIT 1
        ];
    }

    public static ContentVersion createFile(
        Account testAccount,
        String title,
        String pathOnClient,
        String body
    ) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = pathOnClient,
            VersionData = Blob.valueOf(body),
            FirstPublishLocationId = testAccount.Id
        );
        insert version;

        return [
            SELECT Id, ContentDocumentId, Title, PathOnClient, FileType, ContentSize,
                   FirstPublishLocationId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
    }

    public static fra__File_Storage__c createFileStorage(
        Account testAccount,
        String name,
        Map<String, Object> fieldValues
    ) {
        SObject entityStorage = createEntityStorage(testAccount);
        fra__File_Storage__c storedFile = new fra__File_Storage__c(
            Name = name
        );
        storedFile.put('fra__Entity_Storage__c', entityStorage.get('Id'));

        if (fieldValues != null) {
            Map<String, Schema.SObjectField> fields =
                fra__File_Storage__c.SObjectType.getDescribe().fields.getMap();
            for (String fieldName : fieldValues.keySet()) {
                if (fields.containsKey(fieldName) &&
                    fields.get(fieldName).getDescribe().isCreateable()) {
                    storedFile.put(fieldName, fieldValues.get(fieldName));
                }
            }
        }
        insert storedFile;
        return storedFile;
    }

    private static SObject createEntityStorage(Account testAccount) {
        Schema.SObjectType entityType =
            Schema.getGlobalDescribe().get('fra__Entity_Storage__c');
        System.assertNotEquals(
            null,
            entityType,
            'Expected managed-package Entity Storage object.'
        );

        SObject entityStorage = entityType.newSObject();
        Map<String, Schema.SObjectField> fields =
            entityType.getDescribe().fields.getMap();

        putIfCreateable(
            entityStorage,
            fields,
            'Name',
            'File Storage Test Entity'
        );
        putIfCreateable(
            entityStorage,
            fields,
            'Record_Id__c',
            String.valueOf(testAccount.Id)
        );
        putIfCreateable(
            entityStorage,
            fields,
            'fra__Record_Id__c',
            String.valueOf(testAccount.Id)
        );
        putIfCreateable(
            entityStorage,
            fields,
            'fra__Object_RecordId__c',
            String.valueOf(testAccount.Id)
        );
        putIfCreateable(
            entityStorage,
            fields,
            'Object_API_Name__c',
            'Account'
        );
        putIfCreateable(
            entityStorage,
            fields,
            'fra__Object_API_Name__c',
            'Account'
        );

        insert entityStorage;
        return entityStorage;
    }

    private static void putIfCreateable(
        SObject record,
        Map<String, Schema.SObjectField> fields,
        String fieldName,
        Object value
    ) {
        if (fields.containsKey(fieldName) &&
            fields.get(fieldName).getDescribe().isCreateable()) {
            record.put(fieldName, value);
        }
    }

    public static Document_Processing_Log__c createProcessingLog(
        Id contentVersionId,
        Boolean readyForAttachment
    ) {
        Document_Processing_Log__c logRecord = new Document_Processing_Log__c(
            Content_Version_Id__c = String.valueOf(contentVersionId),
            Is_Active__c = true,
            Ready_for_Attachment__c = readyForAttachment
        );
        insert logRecord;
        return logRecord;
    }

    public static void ensureGeminiSettings() {
        Gemini_AI_Settings__c settings = Gemini_AI_Settings__c.getOrgDefaults();
        if (settings == null) {
            settings = new Gemini_AI_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId()
            );
        }
        settings.API_Key__c = 'test-api-key';
        settings.Endpoint__c = 'https://example.test/gemini';
        upsert settings;
    }

    public static SObject ensureGoogleDriveConfig() {
        Schema.SObjectType configType =
            Schema.getGlobalDescribe().get('fra__File_Storage_Setup_Config__c');
        System.assertNotEquals(null, configType, 'Expected File Storage setup config object.');

        Map<String, Schema.SObjectField> fields =
            configType.getDescribe().fields.getMap();
        String activeField = fields.containsKey('fra__Active__c')
            ? 'fra__Active__c'
            : 'Active__c';
        String credentialField = fields.containsKey('fra__Drive_Specific_Credential__c')
            ? 'fra__Drive_Specific_Credential__c'
            : 'Drive_Specific_Credential__c';

        List<SObject> existing = Database.query(
            'SELECT Id, Name, ' + activeField + ', ' + credentialField +
            ' FROM fra__File_Storage_Setup_Config__c' +
            ' WHERE Name = \'Google Drive\' LIMIT 1'
        );

        SObject config = existing.isEmpty() ? configType.newSObject() : existing[0];
        if (existing.isEmpty()) {
            config.put('Name', 'Google Drive');
        }
        config.put(activeField, true);
        config.put(credentialField, 'Test_Google_Drive');
        upsert config;
        return config;
    }
}