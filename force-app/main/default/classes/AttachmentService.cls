public with sharing class AttachmentService {
    public static void createAttachment(String jsonData, String contentVersionId) {
        try {
            ContentVersion cv = [
                SELECT Id, Title, FirstPublishLocationId
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];

            Document_Processing_Log__c logRecord = new Document_Processing_Log__c();
            logRecord.Content_Version_Id__c = contentVersionId;
            logRecord.Current_Status__c = 'Attachment Created';
            logRecord.Error_Message__c = null;
            logRecord.Is_Active__c = true;
            upsert logRecord Content_Version_Id__c;

            logRecord = [
                SELECT Id, Attachment_Id__c
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c = :contentVersionId
                LIMIT 1
            ];

            if (String.isNotBlank(logRecord.Attachment_Id__c)) {
                delete [
                    SELECT Id
                    FROM Attachment
                    WHERE Id = :logRecord.Attachment_Id__c
                    LIMIT 1
                ];
            }

            Attachment att = new Attachment();
            att.Name = cv.Title + '.json';
            att.Body = Blob.valueOf(jsonData);
            att.ParentId = logRecord.Id;
            att.ContentType = 'application/json';
            att.Description = 'Internal document-processing payload. Do not sync to Google Drive.';
            insert att;

            logRecord.Attachment_Id__c = att.Id;
            logRecord.Attachment_Created_On__c = System.now();
            logRecord.Ready_for_Ai_Naming__c = true;
            update logRecord;

            System.debug('Processing Log Updated');

            Document_Processing_Log__c latestLog = [
                SELECT Id,
                       AI_Naming_Completed_On__c,
                       Content_Version_Id__c,
                       Attachment_Id__c,
                       Attachment_Created_On__c,
                       Drive_Sync_Completed_On__c,
                       Current_Status__c,
                       Retry_Count__c
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c = :contentVersionId
                LIMIT 1
            ];

            if (latestLog.AI_Naming_Completed_On__c == null) {
                System.debug('AI Naming Pending');
            }
        } catch (Exception ex) {
            System.debug('Error In AttachmentService');
            System.debug(ex.getMessage());

            Document_Processing_Log__c errorLog = new Document_Processing_Log__c();
            errorLog.Content_Version_Id__c = contentVersionId;
            errorLog.Current_Status__c = 'Attachment Failed';
            errorLog.Error_Message__c = ex.getMessage();
            errorLog.Is_Active__c = true;
            upsert errorLog Content_Version_Id__c;
        }
    }
}