public without sharing class FileStoragePublicUrlBackfillBatch
implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful, Schedulable {
    
    
    public static final Integer DEFAULT_BATCH_SIZE = 40;
    @TestVisible
    private static Boolean skipScheduledBatchExecutionForTest = false;
    @TestVisible
    private static Boolean limitStartQueryForTest = false;
    private Integer processedCount = 0;
    private Integer successCount = 0;
    private Integer failureCount = 0;
    private Boolean sendToPortal;
    private Datetime serviceDateTime;
    
    public FileStoragePublicUrlBackfillBatch() {
        this(true, null);
    }
    
    public FileStoragePublicUrlBackfillBatch(Boolean sendToPortal) {
        this(sendToPortal, null);
    }
    
    public FileStoragePublicUrlBackfillBatch(
        Boolean sendToPortal,
        Datetime serviceDateTime
    ) {
        this.sendToPortal = sendToPortal == null ? true : sendToPortal;
        this.serviceDateTime = serviceDateTime;
    }
    
    public Database.QueryLocator start(Database.BatchableContext context) {
        System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlBackfillBatch.start invoked.');
        
        String query =
            'SELECT Id, fra__File_Id__c, fra__File_Public_Url__c, fra__Uploaded_Drive__c, ' +
            'fra__Internal_File_Id__c ' +
            'FROM fra__File_Storage__c ' +
            'WHERE fra__File_Id__c != null ' +
            'AND fra__Uploaded_Drive__c = \'Google Drive\' ' +
            'AND Public_Url_Chekbox__c = false';
        if (Test.isRunningTest() && limitStartQueryForTest) {
            query += ' LIMIT 1';
        }
        
        System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlBackfillBatch query=' + query);
        return Database.getQueryLocator(query); 
    }
    
    
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlBackfillBatch.execute invoked. Scope size=' + (scope == null ? 0 : scope.size()));
        
        if (scope == null || scope.isEmpty()) {
            return;
        }
        
        GoogleDriveConfig config = getActiveGoogleDriveConfig();
        if (config == null) {
            System.debug(LoggingLevel.WARN, 'FileStoragePublicUrlBackfillBatch skipped scope. Active Google Drive config was not found.');
            return;
        }
        if (String.isBlank(config.driveSpecificCredential)) {
            System.debug(LoggingLevel.WARN, 'FileStoragePublicUrlBackfillBatch skipped scope. Active Google Drive config has no credential.');
            return;
        }
        if (!GoogleDrivePublicUrlService.namedCredentialExists(config.driveSpecificCredential)) {
            System.debug(LoggingLevel.WARN, 'FileStoragePublicUrlBackfillBatch skipped scope. Named Credential was not found: ' + config.driveSpecificCredential);
            return;
        }
        
        Set<Id> cvIds = new Set<Id>();
        for (SObject fs : scope) {
            Id cvId = (Id) fs.get('fra__Internal_File_Id__c');
            if (cvId != null) cvIds.add(cvId);
        }
        Map<Id, String> cvDescMap = new Map<Id, String>();
        Map<Id, String> cvSourceTypeMap = new Map<Id, String>();
        Map<Id, String> cvDocTypeMap = new Map<Id, String>();
        Map<Id, DateTime> cvDateMap = new Map<Id, DateTime>();
        
        for (ContentVersion cv : [
            SELECT Id, Description, Service_Date_Time__c, Source_Type__c, Category__c 
            FROM ContentVersion 
            WHERE Id IN :cvIds
        ]) {
            cvDescMap.put(cv.Id, cv.Description);
            cvSourceTypeMap.put(cv.Id, cv.Source_Type__c);
            cvDocTypeMap.put(cv.Id, cv.Category__c);
            cvDateMap.put(cv.Id, cv.Service_Date_Time__c);
        }
        
        List<SObject> recordsToUpdate = new List<SObject>();
        for (SObject fileStorage : scope) {
            processedCount++;
            
            Id recordId = (Id) fileStorage.get('Id');
            String fileId = (String) fileStorage.get('fra__File_Id__c');
            String existingPublicUrl = (String) fileStorage.get('fra__File_Public_Url__c');
            String uploadedDrive = (String) fileStorage.get('fra__Uploaded_Drive__c');
            
            if (String.isBlank(fileId)) {
                System.debug(LoggingLevel.DEBUG, 'Skipping File Storage record with blank file id. Id=' + recordId);
                continue;
            }
            if (String.isNotBlank(existingPublicUrl)) {
                System.debug(LoggingLevel.DEBUG, 'Skipping File Storage record with existing public URL. Id=' + recordId);
                continue;
            }
            if (uploadedDrive != 'Google Drive') {
                System.debug(LoggingLevel.DEBUG, 'Skipping File Storage record because Uploaded Drive is not Google Drive. Id=' + recordId + ', UploadedDrive=' + uploadedDrive);
                continue;
            }
            
            try {
                System.debug(LoggingLevel.DEBUG, 'Generating public URL for File Storage record. Id=' + recordId + ', FileId=' + fileId);
                String publicUrl = GoogleDrivePublicUrlService.getPublicUrl(config.driveSpecificCredential, fileId);
                if (String.isBlank(publicUrl)) {
                    System.debug(LoggingLevel.WARN, 'Generated public URL was blank. Id=' + recordId);
                    failureCount++;
                    continue;
                }
                
                SObject updateRecord = Schema.getGlobalDescribe().get('fra__File_Storage__c').newSObject(recordId);
                updateRecord.put('fra__File_Public_Url__c', publicUrl);
                updateRecord.put('Send_to_Portal__c', sendToPortal);
                
                Id cvId = (Id) fileStorage.get('fra__Internal_File_Id__c');
                if (cvId != null) {
                    if (cvDescMap.containsKey(cvId) && String.isNotBlank(cvDescMap.get(cvId))) {
                        updateRecord.put('Description__c', cvDescMap.get(cvId));
                    }
                    if (cvSourceTypeMap.containsKey(cvId) && String.isNotBlank(cvSourceTypeMap.get(cvId))) {
                        updateRecord.put('Source_Type__c', cvSourceTypeMap.get(cvId));
                    }
                    if (cvDocTypeMap.containsKey(cvId) && String.isNotBlank(cvDocTypeMap.get(cvId))) {
                        updateRecord.put('Category__c', cvDocTypeMap.get(cvId));
                    }
                    DateTime dateToSet = (cvDateMap.containsKey(cvId) && cvDateMap.get(cvId) != null)
                        ? cvDateMap.get(cvId)
                        : serviceDateTime;
                    if (dateToSet != null) {
                        updateRecord.put('Service_Date_Time__c', dateToSet);
                    }
                }
                recordsToUpdate.add(updateRecord);
            } catch (Exception ex) {
                failureCount++;
                System.debug(LoggingLevel.ERROR, 'Public URL generation failed for File Storage record. Id=' + recordId + ', Error=' + ex.getMessage());
            }
        }
        
        if (recordsToUpdate.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlBackfillBatch found no records to update in this scope.');
            return;
        }
        
        Database.SaveResult[] results = Database.update(recordsToUpdate, false);
        for (Integer i = 0; i < results.size(); i++) {
            Id recordId = (Id) recordsToUpdate[i].get('Id');
            if (results[i].isSuccess()) {
                successCount++;
                System.debug(LoggingLevel.DEBUG, 'Updated File Storage public URL. Id=' + recordId);
            } else {
                failureCount++;
                for (Database.Error error : results[i].getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Failed to update File Storage public URL. Id=' + recordId + ', Error=' + error.getMessage());
                }
            }
        }
    }
    
    public void finish(Database.BatchableContext context) {
        System.debug(
            LoggingLevel.DEBUG,
            'FileStoragePublicUrlBackfillBatch finished. Processed=' + processedCount +
            ', Success=' + successCount +
            ', Failures=' + failureCount
        );
    }
    
    public void execute(SchedulableContext context) {
        System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlBackfillBatch scheduled execution started.');
        if (Test.isRunningTest() && skipScheduledBatchExecutionForTest) {
            System.debug(LoggingLevel.DEBUG, 'FileStoragePublicUrlBackfillBatch scheduled batch execution skipped for test.');
            return;
        }
        Database.executeBatch(
            new FileStoragePublicUrlBackfillBatch(sendToPortal, serviceDateTime),
            DEFAULT_BATCH_SIZE
        );
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