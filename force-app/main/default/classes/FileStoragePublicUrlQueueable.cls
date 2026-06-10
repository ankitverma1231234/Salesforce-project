public without sharing class FileStoragePublicUrlQueueable implements Queueable, Database.AllowsCallouts {
    private static final Integer MAX_RECORDS_PER_EXECUTION = 40;
    private final List<Id> fileStorageIds;

    public FileStoragePublicUrlQueueable(Set<Id> fileStorageIds) {
        this.fileStorageIds = fileStorageIds == null ? new List<Id>() : new List<Id>(fileStorageIds);
    }

    public FileStoragePublicUrlQueueable(List<Id> fileStorageIds) {
        this.fileStorageIds = fileStorageIds == null ? new List<Id>() : new List<Id>(fileStorageIds);
    }

    public static Boolean hasActiveGoogleDriveConfiguration() {
        GoogleDriveConfig config = getActiveGoogleDriveConfig();
        return config != null && String.isNotBlank(config.driveSpecificCredential);
    }

    public void execute(QueueableContext context) {
        System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlQueueable started. Total ids=' + fileStorageIds.size());

        if (fileStorageIds.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlQueueable skipped because no ids were provided.');
            return;
        }

        List<Id> currentIds = new List<Id>();
        List<Id> remainingIds = new List<Id>();
        for (Integer i = 0; i < fileStorageIds.size(); i++) {
            if (i < MAX_RECORDS_PER_EXECUTION) {
                currentIds.add(fileStorageIds[i]);
            } else {
                remainingIds.add(fileStorageIds[i]);
            }
        }

        GoogleDriveConfig config = getActiveGoogleDriveConfig();
        if (config == null) {
            System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlQueueable skipped. Active Google Drive file storage config was not found.');
            return;
        }
        if (String.isBlank(config.driveSpecificCredential)) {
            System.debug(LoggingLevel.WARN, 'FileStoragePublicUrlQueueable skipped. Active Google Drive config has no Drive Specific Credential.');
            return;
        }
        if (!GoogleDrivePublicUrlService.namedCredentialExists(config.driveSpecificCredential)) {
            System.debug(LoggingLevel.WARN, 'FileStoragePublicUrlQueueable skipped. Named Credential was not found: ' + config.driveSpecificCredential);
            return;
        }

        List<SObject> recordsToUpdate = new List<SObject>();
        for (SObject fileStorage : queryEligibleFileStorageRecords(currentIds)) {
            Id recordId = (Id) fileStorage.get('Id');
            String fileId = (String) fileStorage.get('fra__File_Id__c');
            String existingPublicUrl = (String) fileStorage.get('fra__File_Public_Url__c');

            if (String.isBlank(fileId)) {
                System.debug(LoggingLevel.DEBUG, 'Queueable skipping blank file id. FileStorageId=' + recordId);
                continue;
            }
            if (String.isNotBlank(existingPublicUrl)) {
                System.debug(LoggingLevel.DEBUG, 'Queueable skipping existing public URL. FileStorageId=' + recordId);
                continue;
            }

            try {
                System.debug(LoggingLevel.DEBUG, 'Generating Google Drive public URL. FileStorageId=' + recordId + ', FileId=' + fileId);
                String publicUrl = GoogleDrivePublicUrlService.getPublicUrl(config.driveSpecificCredential, fileId);
                if (String.isBlank(publicUrl)) {
                    System.debug(LoggingLevel.WARN, 'Google Drive public URL generation returned blank. FileStorageId=' + recordId);
                    continue;
                }

                SObject updateRecord = Schema.getGlobalDescribe().get('fra__File_Storage__c').newSObject(recordId);
                updateRecord.put('fra__File_Public_Url__c', publicUrl);
                recordsToUpdate.add(updateRecord);
                System.debug(LoggingLevel.DEBUG, 'Prepared public URL update. FileStorageId=' + recordId + ', PublicUrl=' + publicUrl);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Failed to generate public URL for FileStorageId=' + recordId + '. Error=' + ex.getMessage());
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(recordsToUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    System.debug(LoggingLevel.DEBUG, 'Updated File Storage public URL. Id=' + recordsToUpdate[i].get('Id'));
                } else {
                    for (Database.Error error : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'Failed to update File Storage public URL. Id=' + recordsToUpdate[i].get('Id') + ', Error=' + error.getMessage());
                    }
                }
            }
        } else {
            System.debug(LoggingLevel.DEBUG, 'No File Storage records needed public URL updates.');
        }

        if (!remainingIds.isEmpty() && !Test.isRunningTest()) {
            System.debug(LoggingLevel.DEBUG, 'Enqueuing next FileStoragePublicUrlQueueable chunk. Remaining=' + remainingIds.size());
            System.enqueueJob(new FileStoragePublicUrlQueueable(remainingIds));
        }
    }

    private static List<SObject> queryEligibleFileStorageRecords(List<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<SObject>();
        }

        String query =
            'SELECT Id, fra__File_Id__c, fra__File_Public_Url__c ' +
            'FROM fra__File_Storage__c ' +
            'WHERE Id IN :ids';

        return Database.query(query);
    }

    private static GoogleDriveConfig getActiveGoogleDriveConfig() {
        Schema.SObjectType configType = Schema.getGlobalDescribe().get('fra__File_Storage_Setup_Config__c');
        if (configType == null) {
            System.debug(LoggingLevel.WARN, 'Config object fra__File_Storage_Setup_Config__c was not found.');
            return null;
        }

        Map<String, Schema.SObjectField> fields = configType.getDescribe().fields.getMap();
        String activeField = getFirstExistingField(fields, new List<String>{ 'fra__Active__c', 'Active__c' });
        String credentialField = getFirstExistingField(fields, new List<String>{ 'fra__Drive_Specific_Credential__c', 'Drive_Specific_Credential__c' });

        if (String.isBlank(activeField) || String.isBlank(credentialField)) {
            System.debug(LoggingLevel.WARN, 'Config fields are missing. activeField=' + activeField + ', credentialField=' + credentialField);
            return null;
        }

        String query =
            'SELECT Id, Name, ' + activeField + ', ' + credentialField + ' ' +
            'FROM fra__File_Storage_Setup_Config__c ' +
            'WHERE Name = \'Google Drive\' AND ' + activeField + ' = true ' +
            'LIMIT 1';

        List<SObject> configs = Database.query(query);
        if (configs.isEmpty()) {
            return null;
        }

        GoogleDriveConfig config = new GoogleDriveConfig();
        config.driveSpecificCredential = (String) configs[0].get(credentialField);
        System.debug(LoggingLevel.DEBUG, 'Active Google Drive config found. Id=' + configs[0].get('Id') + ', NamedCredential=' + config.driveSpecificCredential);
        return config;
    }

    private static String getFirstExistingField(Map<String, Schema.SObjectField> fields, List<String> candidates) {
        for (String candidate : candidates) {
            if (fields.containsKey(candidate)) {
                return candidate;
            }
        }
        return null;
    }

    private class GoogleDriveConfig {
        String driveSpecificCredential;
    }
}