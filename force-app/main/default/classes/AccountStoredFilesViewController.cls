public with sharing class AccountStoredFilesViewController {
    @TestVisible
    private static List<SObject> storedFilesForTest;

    public class StoredFileRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String fileType;
        @AuraEnabled public String fileSize;
        @AuraEnabled public String fileUrl;
        @AuraEnabled public String viewUrl;
        @AuraEnabled public String fileId;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public Boolean sendToPortal;
        @AuraEnabled public String serviceDateDisplay;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String category;
        @AuraEnabled public String internalFileId;
        @AuraEnabled public String relatedSummaryFile;
    }

    @AuraEnabled(cacheable=true)
    public static List<StoredFileRow> getStoredFiles(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        Schema.DescribeSObjectResult objectDescribe = fra__File_Storage__c.SObjectType.getDescribe();
        if (!objectDescribe.isAccessible()) {
            throw new AuraHandledException('You do not have permission to view file storage records.');
        }

        Map<String, Schema.SObjectField> fields = objectDescribe.fields.getMap();
        requireAccessibleField(fields, 'fra__Object_RecordId__c');

        List<String> selectableFields = new List<String>{ 'Id' };
        addAccessibleField(selectableFields, fields, 'Name');
        addAccessibleField(selectableFields, fields, 'fra__File_Type__c');
        addAccessibleField(selectableFields, fields, 'fra__File_Size__c');
        addAccessibleField(selectableFields, fields, 'fra__File_Public_Url__c');
        addAccessibleField(selectableFields, fields, 'fra__View_File__c');
        addAccessibleField(selectableFields, fields, 'fra__File_Id__c');
        addAccessibleField(selectableFields, fields, 'LastModifiedDate');
        addAccessibleField(selectableFields, fields, 'Send_to_Portal__c');
        addAccessibleField(selectableFields, fields, 'Date_of_Service_Display__c');
        addAccessibleField(selectableFields, fields, 'Source_Type__c');
        addAccessibleField(selectableFields, fields, 'Category__c');
        addAccessibleField(selectableFields, fields, 'fra__Internal_File_Id__c');
        addAccessibleField(selectableFields, fields, 'Related_Summary_File__c');

        String query =
            'SELECT ' + String.join(selectableFields, ', ') +
            ' FROM fra__File_Storage__c' +
            ' WHERE fra__Object_RecordId__c = :recordId' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY LastModifiedDate DESC';

        List<SObject> storedFiles = Test.isRunningTest() && storedFilesForTest != null
            ? storedFilesForTest
            : Database.query(query);

        List<StoredFileRow> rows = new List<StoredFileRow>();
        for (SObject storedFile : storedFiles) {
            StoredFileRow row = new StoredFileRow();
            row.id = (Id) storedFile.get('Id');
            row.name = getStringValue(storedFile, fields, 'Name');
            row.fileType = getStringValue(storedFile, fields, 'fra__File_Type__c');
            row.fileSize = getStringValue(storedFile, fields, 'fra__File_Size__c');
            row.fileUrl = getStringValue(storedFile, fields, 'fra__File_Public_Url__c');
            row.viewUrl = getPreviewUrl(storedFile, fields);
            row.fileId = getStringValue(storedFile, fields, 'fra__File_Id__c');
            row.lastModifiedDate = fields.containsKey('LastModifiedDate')
                ? (Datetime) storedFile.get('LastModifiedDate')
                : null;
            row.sendToPortal = getBooleanValue(storedFile, fields, 'Send_to_Portal__c');
            row.serviceDateDisplay = getStringValue(storedFile, fields, 'Date_of_Service_Display__c');
            row.sourceType = getStringValue(storedFile, fields, 'Source_Type__c');
            row.category = getStringValue(storedFile, fields, 'Category__c');
            row.internalFileId = getStringValue(storedFile, fields, 'fra__Internal_File_Id__c');
            row.relatedSummaryFile = getStringValue(storedFile, fields, 'Related_Summary_File__c');
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void updateSendToPortal(Id fileStorageId, Boolean value) {
        if (fileStorageId == null) {
            throw new AuraHandledException('File record Id is required.');
        }

        Schema.DescribeFieldResult fieldDescribe = fra__File_Storage__c.Send_to_Portal__c.getDescribe();
        if (!fieldDescribe.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update the Send to Portal field.');
        }

        fra__File_Storage__c record = new fra__File_Storage__c(
            Id = fileStorageId,
            Send_to_Portal__c = value == true
        );

        try {
            update record;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static void deleteStoredFile(Id fileStorageId) {
        if (fileStorageId == null) {
            throw new AuraHandledException('File record Id is required.');
        }

        Schema.DescribeSObjectResult objectDescribe = fra__File_Storage__c.SObjectType.getDescribe();
        if (!objectDescribe.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete file storage records.');
        }

        List<fra__File_Storage__c> files = [
            SELECT Id
            FROM fra__File_Storage__c
            WHERE Id = :fileStorageId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (files.isEmpty()) {
            throw new AuraHandledException('File record was not found or is not accessible.');
        }

        delete files[0];
    }

    @AuraEnabled
    public static void deleteStoredFiles(List<Id> fileStorageIds) {
        if (fileStorageIds == null || fileStorageIds.isEmpty()) {
            throw new AuraHandledException('At least one file record Id is required.');
        }

        Schema.DescribeSObjectResult objectDescribe = fra__File_Storage__c.SObjectType.getDescribe();
        if (!objectDescribe.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete file storage records.');
        }

        List<fra__File_Storage__c> filesToDelete = [
            SELECT Id
            FROM fra__File_Storage__c
            WHERE Id IN :fileStorageIds
            WITH SECURITY_ENFORCED
        ];

        if (filesToDelete.isEmpty()) {
            throw new AuraHandledException('No file records were found or accessible for deletion.');
        }

        delete filesToDelete;
    }

    private static void addAccessibleField(
        List<String> selectableFields,
        Map<String, Schema.SObjectField> fields,
        String fieldName
    ) {
        if (fields.containsKey(fieldName) && fields.get(fieldName).getDescribe().isAccessible()) {
            selectableFields.add(fieldName);
        }
    }

    private static void requireAccessibleField(Map<String, Schema.SObjectField> fields, String fieldName) {
        if (!fields.containsKey(fieldName) || !fields.get(fieldName).getDescribe().isAccessible()) {
            throw new AuraHandledException('You do not have permission to access required file storage fields.');
        }
    }

    private static String getStringValue(SObject row, Map<String, Schema.SObjectField> fields, String fieldName) {
        if (!fields.containsKey(fieldName) || !fields.get(fieldName).getDescribe().isAccessible()) {
            return null;
        }
        Object value = row.get(fieldName);
        return value == null ? null : String.valueOf(value);
    }

    private static Boolean getBooleanValue(SObject row, Map<String, Schema.SObjectField> fields, String fieldName) {
        if (!fields.containsKey(fieldName) || !fields.get(fieldName).getDescribe().isAccessible()) {
            return false;
        }
        Object value = row.get(fieldName);
        return value == null ? false : (Boolean) value;
    }

    private static String getPreviewUrl(SObject row, Map<String, Schema.SObjectField> fields) {
        String viewFileValue = getStringValue(row, fields, 'fra__View_File__c');
        if (String.isBlank(viewFileValue)) {
            return getStringValue(row, fields, 'fra__File_Public_Url__c');
        }

        String lowerValue = viewFileValue.toLowerCase();
        Integer hrefStart = lowerValue.indexOf('href="');
        String quoteValue = '"';
        if (hrefStart < 0) {
            hrefStart = lowerValue.indexOf('href=\'');
            quoteValue = '\'';
        }
        if (hrefStart < 0) {
            return viewFileValue;
        }

        Integer urlStart = hrefStart + 6;
        Integer urlEnd = viewFileValue.indexOf(quoteValue, urlStart);
        if (urlEnd <= urlStart) {
            return viewFileValue;
        }

        return viewFileValue.substring(urlStart, urlEnd).replace('&amp;', '&');
    }
}