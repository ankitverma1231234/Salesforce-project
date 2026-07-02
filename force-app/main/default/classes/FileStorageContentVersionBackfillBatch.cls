global with sharing class FileStorageContentVersionBackfillBatch
implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    private Integer processedCount = 0;
    private Integer updatedCount   = 0;
    private Integer skippedCount   = 0;
    private Integer failedCount    = 0;

    global Database.QueryLocator start(Database.BatchableContext bc) {

        return Database.getQueryLocator([
            SELECT
                Id,
                Name,
                fra__Internal_File_Id__c,
                Source_Type__c,
                Category__c,
                Service_Date_Time__c,
                Date_of_Service_Display__c,
                Document_Type__c,
                Send_to_Portal__c,
                Related_Summary_file__c,
                Fra_AI_Source_File_Id__c,
                Document_Id__c
            FROM fra__File_Storage__c
            WHERE fra__Internal_File_Id__c != NULL
            AND Source_Type__c = NULL
        ]);
    }

    global void execute(
        Database.BatchableContext bc,
        List<fra__File_Storage__c> scope
    ) {

        processedCount += scope.size();

        Set<Id> contentVersionIds = new Set<Id>();

        for (fra__File_Storage__c fs : scope) {
            if (String.isNotBlank(fs.fra__Internal_File_Id__c)) {
                try {
                    contentVersionIds.add(
                        (Id)fs.fra__Internal_File_Id__c
                    );
                } catch (Exception e) {
                    System.debug(
                        LoggingLevel.WARN,
                        'Invalid ContentVersion Id on File Storage '
                        + fs.Id
                    );
                }
            }
        }

        if (contentVersionIds.isEmpty()) {
            skippedCount += scope.size();
            return;
        }

        Map<Id, ContentVersion> contentVersionMap =
            new Map<Id, ContentVersion>([
                SELECT
                    Id,
                    Source_Type__c,
                    Category__c,
                    Send_File_to_Portal__c,
                    Service_Date_Time__c,
                    Date_of_Service_Display__c,
                    Related_File__c,
                    Description,
                    Organization_Name__c
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
            ]);

        Set<Id> relatedContentDocumentIds = new Set<Id>();

        for (ContentVersion cv : contentVersionMap.values()) {

            if (String.isNotBlank(cv.Related_File__c)) {

                try {
                    relatedContentDocumentIds.add(
                        (Id)cv.Related_File__c
                    );

                } catch(Exception e) {

                    System.debug(
                        LoggingLevel.WARN,
                        'Invalid Related File'
                    );
                }
            }
        }

        Map<Id,Id> contentDocumentToLatestVersionMap =
            new Map<Id,Id>();

        if(!relatedContentDocumentIds.isEmpty()){

            for(ContentVersion relatedCv : [

                SELECT Id,ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN
                :relatedContentDocumentIds
                AND IsLatest = true

            ]){

                contentDocumentToLatestVersionMap.put(
                    relatedCv.ContentDocumentId,
                    relatedCv.Id
                );
            }
        }

        List<fra__File_Storage__c> recordsToUpdate =
            new List<fra__File_Storage__c>();

        for(fra__File_Storage__c fs : scope){

            ContentVersion cv =
                contentVersionMap.get(
                    (Id)fs.fra__Internal_File_Id__c
                );

            if(cv == null){

                skippedCount++;

                continue;
            }

            fs.Source_Type__c       = cv.Source_Type__c;
            fs.Category__c          = cv.Category__c;
            fs.Service_Date_Time__c = cv.Service_Date_Time__c;
            fs.Organization_Name__c = cv.Organization_Name__c;
            fs.Description__c       = cv.Description;
            fs.Send_to_Portal__c    = cv.Send_File_to_Portal__c;

            if(String.isNotBlank(cv.Related_File__c)){

                Id latestVersionId =
                    contentDocumentToLatestVersionMap.get(
                        (Id)cv.Related_File__c
                    );

                if(latestVersionId != null){

                    fs.Related_Summary_file__c =
                        String.valueOf(latestVersionId);
                }
            }

            recordsToUpdate.add(fs);
        }

        Set<String> relatedSummaryVersionIds =
            new Set<String>();

        for(fra__File_Storage__c fs : recordsToUpdate){

            if(String.isNotBlank(
                fs.Related_Summary_file__c)){

                relatedSummaryVersionIds.add(
                    fs.Related_Summary_file__c
                );
            }
        }

        Map<String,String> parentFileStorageIdByVersionId =
            new Map<String,String>();

        if(!relatedSummaryVersionIds.isEmpty()){

            for(fra__File_Storage__c parentFs : [

                SELECT Id,
                       fra__Internal_File_Id__c
                FROM fra__File_Storage__c
                WHERE fra__Internal_File_Id__c
                IN :relatedSummaryVersionIds

            ]){

                parentFileStorageIdByVersionId.put(
                    parentFs.fra__Internal_File_Id__c,
                    parentFs.Id
                );
            }
        }

        for(fra__File_Storage__c fs : recordsToUpdate){

            if(String.isNotBlank(
                fs.Related_Summary_file__c)){

                String parentId =
                    parentFileStorageIdByVersionId.get(
                        fs.Related_Summary_file__c
                    );

                if(parentId != null){

                    fs.Fra_AI_Source_File_Id__c =
                        parentId;
                }
            }
        }

        if(!recordsToUpdate.isEmpty()){

            Database.SaveResult[] results =
                Database.update(
                    recordsToUpdate,
                    false
                );

            for(Database.SaveResult sr : results){

                if(sr.isSuccess()){

                    updatedCount++;

                }else{

                    failedCount++;

                    for(Database.Error err :
                        sr.getErrors()){

                        System.debug(
                            LoggingLevel.ERROR,
                            err.getMessage()
                        );
                    }
                }
            }
        }
    }

    global void finish(Database.BatchableContext bc) {

        Database.executeBatch(
            new FileStoragePublicUrlBackfillBatch(),
            40
        );

        System.debug(
            'Processed=' + processedCount +
            ' Updated=' + updatedCount +
            ' Skipped=' + skippedCount +
            ' Failed=' + failedCount
        );
    }

    // Schedulable execution
    global void execute(
        SchedulableContext context
    ){

        Database.executeBatch(
            new FileStorageContentVersionBackfillBatch(),
            200
        );
    }

    // Schedule helper
    public static void scheduleJob(
        String jobName,
        String cronExpression
    ){

        System.schedule(
            jobName,
            cronExpression,
            new FileStorageContentVersionBackfillBatch()
        );
    }

    // Stop specific job
    public static void stopJob(
        String jobName
    ){

        List<CronTrigger> jobs=[

            SELECT Id,
                   CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ];

        for(CronTrigger ct : jobs){

            System.abortJob(ct.Id);
        }
    }

    // Stop all jobs
    public static void stopAllJobs(){

        List<CronTrigger> jobs=[

            SELECT Id,
                   CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name
            LIKE 'FileStorage%'
        ];

        for(CronTrigger ct : jobs){

            System.abortJob(ct.Id);
        }
    }
}