public with sharing class AttachmentService {

    public static void createAttachment(
        String jsonData,
        String contentVersionId
    ) {
        try {

            ContentVersion cv = [

                SELECT Id,
                       Title,
                       FirstPublishLocationId

                FROM ContentVersion

                WHERE Id = :contentVersionId

                LIMIT 1
            ];

            /*
             * Create Attachment
             */
            Attachment att = new Attachment();

            att.Name =
                cv.Title + '.json';

            att.Body =
                Blob.valueOf(jsonData);

            att.ParentId =
                cv.FirstPublishLocationId;

            insert att;

            /*
             * Upsert Processing Log
             */
            Document_Processing_Log__c logRecord =
                new Document_Processing_Log__c();

            logRecord.Content_Version_Id__c =
                contentVersionId;

            logRecord.Attachment_Id__c =
                att.Id;

            logRecord.Attachment_Created_On__c =
                System.now();

            logRecord.Current_Status__c =
                'Attachment Created';

            logRecord.Error_Message__c =
                null;

            logRecord.Is_Active__c =
                true;

            upsert logRecord
                Content_Version_Id__c;

            System.debug(
                'Processing Log Updated'
            );

            /*
             * Query Latest Processing Log
             */
            Document_Processing_Log__c latestLog = [

                SELECT Id,
                       OwnerId,
                       IsDeleted,
                       Name,
                       CreatedDate,
                       CreatedById,
                       LastModifiedDate,
                       LastModifiedById,
                       SystemModstamp,
                       LastViewedDate,
                       LastReferencedDate,
                       AI_Naming_Completed_On__c,
                       AI_Summary_Completed_On__c,
                       Attachment_Created_On__c,
                       Attachment_Id__c,
                       Content_Version_Id__c,
                       Current_Status__c,
                       Drive_Sync_Completed_On__c,
                       Error_Message__c,
                       Is_Active__c,
                       Metriport_Id__c,
                       Processing_Duration_MS__c,
                       Processing_Stages__c,
                       Related_Record_Id__c,
                       Retry_Count__c

                FROM Document_Processing_Log__c

                WHERE Content_Version_Id__c
                = :contentVersionId

                LIMIT 1
            ];

            /*
             * If AI Naming Not Completed
             * Trigger Dummy AI Naming Batch
             */
            if(latestLog
                .AI_Naming_Completed_On__c
                == null) {

                System.debug(
                    'AI Naming Pending'
                );

                /*Database.executeBatch(
                    new DummyAINamingBatch(
                        contentVersionId
                    ),
                    1
                );*/
            }

        } 
catch(Exception ex) {

            System.debug(
                'Error In AttachmentService'
            );

            System.debug(ex.getMessage());

            /*
             * Error Log Update
             */
            Document_Processing_Log__c errorLog =
                new Document_Processing_Log__c();

            errorLog.Content_Version_Id__c =
                contentVersionId;

            errorLog.Current_Status__c =
                'Attachment Failed';

            errorLog.Error_Message__c =
                ex.getMessage();

            errorLog.Is_Active__c =
                true;

            upsert errorLog
                Content_Version_Id__c;
        }
        Database.executeBatch(new AiFileNamingDailyJob(contentVersionId), 1);
    }
}