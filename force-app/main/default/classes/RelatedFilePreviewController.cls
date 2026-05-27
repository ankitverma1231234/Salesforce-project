public with sharing class RelatedFilePreviewController {

    @AuraEnabled(cacheable=true)
    public static FileWrapper getRelatedFile(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('ContentDocumentId is required.');
        }

        List<ContentVersion> versions = [
            SELECT Id,
                   Title,
                   FileType,
                   ContentDocumentId
            FROM ContentVersion
            WHERE Related_File__c = :contentDocumentId
              AND IsLatest = true
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            return null;
        }

        ContentVersion cv = versions[0];
        FileWrapper fw = new FileWrapper();
        fw.contentVersionId = cv.Id;
        fw.contentDocumentId = cv.ContentDocumentId;
        fw.title = cv.Title;
        fw.fileType = cv.FileType != null ? cv.FileType.toLowerCase() : '';
        return fw;
    }

    public class FileWrapper {
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileType;
    }
}