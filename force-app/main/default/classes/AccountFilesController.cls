public with sharing class AccountFilesController {

    @AuraEnabled(cacheable=true)
    public static List<FileWrapper> getAccountFiles(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        List<ContentVersion> versions = [
            SELECT Id,
                   ContentDocumentId,
                   Title,
                   FileType,
                   Description,
                   Organization_Name__c,
                   Send_File_to_Portal__c,
                   Date_of_Service_Display__c,
                   Source_Type__c,
                   Related_File__c
            FROM ContentVersion
            WHERE FirstPublishLocationId = :accountId
              AND IsLatest = true
            ORDER BY LastModifiedDate DESC
        ];

        List<FileWrapper> files = new List<FileWrapper>();
        for (ContentVersion cv : versions) {
            FileWrapper fw = new FileWrapper();
            fw.contentVersionId = cv.Id;
            fw.contentDocumentId = cv.ContentDocumentId;
            fw.title = cv.Title;
            fw.fileType = cv.FileType;
            fw.description = cv.Description;
            fw.provider = cv.Organization_Name__c;
            fw.sendFileToPortal = cv.Send_File_to_Portal__c;
            fw.source = cv.Source_Type__c;
            fw.relatedFile = cv.Related_File__c;
            fw.fileExtension = cv.FileType != null ? cv.FileType.toLowerCase() : '';
            fw.serviceDateStr = cv.Date_of_Service_Display__c;
            files.add(fw);
        }

        return files;
    }

    @AuraEnabled
    public static void deleteFiles(List<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            throw new AuraHandledException('No files selected for deletion.');
        }

        try {
            List<ContentDocument> docsToDelete = [
                SELECT Id FROM ContentDocument WHERE Id IN :contentDocumentIds
            ];
            if (!docsToDelete.isEmpty()) {
                delete docsToDelete;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting files: ' + e.getMessage());
        }
    }

    public class FileWrapper {
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileType;
        @AuraEnabled public String description;
        @AuraEnabled public String provider;
        @AuraEnabled public Boolean sendFileToPortal;
        @AuraEnabled public Date serviceDateStr;
        @AuraEnabled public String source;
        @AuraEnabled public String relatedFile;
        @AuraEnabled public String fileExtension;
    }
}