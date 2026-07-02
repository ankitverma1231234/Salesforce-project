@RestResource(urlMapping='/account/unsynced-files/*')
global without sharing class AccountUnsyncedFilesRestResource {
    
    @TestVisible
    private static Boolean forceFailure = false;

    @TestVisible
    private static Boolean forceNoUnsyncedFiles = false;

    @TestVisible
    private static Boolean forceNoAccountLinks = false;

    @TestVisible
    private static Boolean forceEmptyPageAfterCount = false;

    @TestVisible
    private static Boolean forceDriveFolderPrimaryQueryFailure = false;

    @TestVisible
    private static Boolean forceDriveFolderFallbackQueryFailure = false;

    private static final Integer DEFAULT_PAGE_SIZE = 200;
    private static final Integer MAX_PAGE_SIZE = 200;
    private static final Integer CONTENT_DISTRIBUTION_NAME_MAX_LENGTH = 100;

    global class AccountFileResponse {
        public String ContentVersionId;
        public String AccountId;
        public String FileType;
        public String DriveFolderId;
        public String PublicUrl;
    }
    
    global class PagedResponse {
        public Integer                   page;
        public Integer                   pageSize;
        public Integer                   returnedCount;
        public Integer                   totalUnsynced;   
        public Integer                   totalFilesToShare;
        public Integer                   totalPages;     
        public Boolean                   hasMore;
        public String                    nextPageUrl;
        public List<AccountFileResponse> records;
    }
    
    private class ErrorResponse {
        public Boolean success;
        public String  message;
    }
    
    @HttpGet
    global static void handleGet() {
        RestResponse res = RestContext.response;
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }
        
        try {
            RestRequest req  = RestContext.request;
            Integer page     = parseIntParam(req, 'page', 1);
            Integer pageSize = parseIntParam(req, 'pageSize', DEFAULT_PAGE_SIZE);

            if (page < 1) page = 1;
            if (pageSize < 1) pageSize = DEFAULT_PAGE_SIZE;
            if (pageSize > MAX_PAGE_SIZE) pageSize = MAX_PAGE_SIZE;

            Integer offset = (page - 1) * pageSize;

            PagedResponse pagedResult = getUnsyncedAccountFiles(page, pageSize, offset);
            writeJson(res, 200, pagedResult);
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                         'AccountUnsyncedFilesRestResource.handleGet failed: ' +
                         ex.getMessage() + '\n' + ex.getStackTraceString()
                        );
            ErrorResponse error = new ErrorResponse();
            error.success = false;
            error.message = 'Unable to retrieve unsynced Account files.';
            writeJson(res, 500, error);
        }
    }
    
    @TestVisible
    private static PagedResponse getUnsyncedAccountFiles() {
        return getUnsyncedAccountFiles(1, DEFAULT_PAGE_SIZE, 0);
    }

    @TestVisible
    private static PagedResponse getUnsyncedAccountFiles(
        Integer page,
        Integer pageSize,
        Integer offset
    ) {
        if (forceFailure) {
            throw new AccountUnsyncedFilesException('Forced test failure.');
        }

        if (page == null || page < 1) page = 1;
        if (pageSize == null || pageSize < 1) pageSize = DEFAULT_PAGE_SIZE;
        if (pageSize > MAX_PAGE_SIZE) pageSize = MAX_PAGE_SIZE;
        if (offset == null || offset < 0) offset = (page - 1) * pageSize;
        
        PagedResponse result = new PagedResponse();
        result.page          = page;
        result.pageSize      = pageSize;
        result.returnedCount = 0;
        result.totalUnsynced = 0;
        result.totalFilesToShare = 0;
        result.totalPages    = 0;
        result.hasMore       = false;
        result.nextPageUrl   = null;
        result.records       = new List<AccountFileResponse>();
        
        Set<Id> syncedIds = getSyncedContentVersionIdsFromFileStorage();
        
        if (forceNoUnsyncedFiles) {
            return result;
        }

        List<ContentVersion> pageCVs = forceEmptyPageAfterCount
            ? new List<ContentVersion>()
            : [
                SELECT Id,
                ContentDocumentId,
                Title,
                FileType,
                FirstPublishLocationId
                FROM   ContentVersion
                WHERE  IsLatest = true
                AND    Ready_For_External_Sync__c = true
                AND    Id NOT IN :syncedIds
                AND    FirstPublishLocationId IN (SELECT Id FROM Account)
                ORDER BY CreatedDate DESC
            ];

        if (pageCVs.isEmpty()) {
            return result;
        }
        
        Set<Id> candidateDocIds = new Set<Id>();
        for (ContentVersion cv : pageCVs) {
            candidateDocIds.add(cv.ContentDocumentId);
        }
        
        Map<Id, Id> docIdToAccountId = new Map<Id, Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM   ContentDocumentLink
            WHERE  ContentDocumentId IN :candidateDocIds
            AND    LinkedEntityId IN (SELECT Id FROM Account)
        ]) {
            if (!docIdToAccountId.containsKey(cdl.ContentDocumentId)) {
                docIdToAccountId.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
            }
        }

        if (forceNoAccountLinks) {
            docIdToAccountId.clear();
        }
        
        List<ContentVersion> linkedVersions   = new List<ContentVersion>();
        Set<Id>              linkedAccountIds = new Set<Id>();
        
        for (ContentVersion cv : pageCVs) {
            Id accountId = docIdToAccountId.get(cv.ContentDocumentId);
            if (accountId == null) continue;
            linkedVersions.add(cv);
            linkedAccountIds.add(accountId);
        }
        
        if (linkedVersions.isEmpty()) {
            return result;
        }
        
        Map<Id, String> driveFolderIdsByAccountId =
            getDriveFolderIdsByAccountId(linkedAccountIds);

        List<ContentVersion> versionsWithDriveFolders = new List<ContentVersion>();
        for (ContentVersion cv : linkedVersions) {
            Id     resolvedAccountId = docIdToAccountId.get(cv.ContentDocumentId);
            String driveFolderId     = driveFolderIdsByAccountId.get(resolvedAccountId);

            if (String.isBlank(driveFolderId)) {
                System.debug(LoggingLevel.DEBUG,
                             'getUnsyncedAccountFiles: skipping CV ' + cv.Id +
                             ' — no DriveFolderId for Account ' + resolvedAccountId
                            );
                continue;
            }

            versionsWithDriveFolders.add(cv);
        }

        if (versionsWithDriveFolders.isEmpty()) {
            return result;
        }

        Integer totalFilesToShare = versionsWithDriveFolders.size();
        result.totalUnsynced      = totalFilesToShare;
        result.totalFilesToShare  = totalFilesToShare;
        result.totalPages         = (Integer) Math.ceil((Decimal) totalFilesToShare / pageSize);
        result.hasMore            = page < result.totalPages;
        result.nextPageUrl        = result.hasMore
            ? '/services/apexrest/account/unsynced-files?page=' +
            (page + 1) + '&pageSize=' + pageSize
            : null;

        if (offset >= totalFilesToShare) {
            return result;
        }

        List<ContentVersion> pageVersions = new List<ContentVersion>();
        Set<Id> pageVersionIds = new Set<Id>();
        Integer endIndex = Math.min(offset + pageSize, totalFilesToShare);
        for (Integer i = offset; i < endIndex; i++) {
            ContentVersion cv = versionsWithDriveFolders[i];
            pageVersions.add(cv);
            pageVersionIds.add(cv.Id);
        }

        Map<Id, String> publicUrlsByVersionId =
            getOrCreatePublicUrls(pageVersions, pageVersionIds);

        for (ContentVersion cv : pageVersions) {
            Id     resolvedAccountId = docIdToAccountId.get(cv.ContentDocumentId);
            String driveFolderId     = driveFolderIdsByAccountId.get(resolvedAccountId);
            String publicUrl         = publicUrlsByVersionId.get(cv.Id);

            if (String.isBlank(publicUrl)) {
                System.debug(LoggingLevel.WARN,
                             'getUnsyncedAccountFiles: skipping CV ' + cv.Id +
                             ' because no ContentDistribution public URL exists or could be created.'
                            );
                continue;
            }

            AccountFileResponse row = new AccountFileResponse();
            row.ContentVersionId = String.valueOf(cv.Id);
            row.AccountId        = String.valueOf(resolvedAccountId);
            row.FileType         = cv.FileType;
            row.DriveFolderId    = driveFolderId;
            row.PublicUrl        = publicUrl;
            result.records.add(row);
        }
        
        result.returnedCount = result.records.size();
        
        System.debug(LoggingLevel.DEBUG,
                     'getUnsyncedAccountFiles: returning ' + result.returnedCount +
                     ' rows for page ' + page +
                     ' of ' + result.totalPages +
                     ' (totalFilesToShare=' + totalFilesToShare + ')'
                    );
        
        return result;
    }
    
   
    private static Set<Id> getSyncedContentVersionIdsFromFileStorage() {
        Set<Id> result = new Set<Id>();
        for (fra__File_Storage__c fs : [
            SELECT fra__Internal_File_Id__c
            FROM   fra__File_Storage__c
            WHERE  fra__Internal_File_Id__c != null
            AND    fra__Internal_File_Id__c LIKE '068%'
        ]) {
            try {
                result.add((Id) fs.fra__Internal_File_Id__c);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                             'getSyncedContentVersionIdsFromFileStorage: bad value [' +
                             fs.fra__Internal_File_Id__c + ']: ' + e.getMessage()
                            );
            }
        }
        return result;
    }
    
    // ── Public URL resolution ─────────────────────────────────────────────────
    private static Map<Id, String> getOrCreatePublicUrls(
        List<ContentVersion> contentVersions,
        Set<Id>              contentVersionIds
    ) {
        Map<Id, String> urlsByVersionId = new Map<Id, String>();
        if (contentVersionIds == null || contentVersionIds.isEmpty()) {
            return urlsByVersionId;
        }
        
        for (ContentDistribution cd : [
            SELECT Id, ContentVersionId, ContentDownloadUrl, DistributionPublicUrl
            FROM   ContentDistribution
            WHERE  ContentVersionId IN :contentVersionIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!urlsByVersionId.containsKey(cd.ContentVersionId)) {
                urlsByVersionId.put(cd.ContentVersionId, preferredPublicUrl(cd));
            }
        }

        List<ContentDistribution> toInsert = new List<ContentDistribution>();
        for (ContentVersion cv : contentVersions) {
            if (urlsByVersionId.containsKey(cv.Id)) continue;
            toInsert.add(new ContentDistribution(
                Name                             = contentDistributionName(cv.Title),
                ContentVersionId                 = cv.Id,
                PreferencesAllowViewInBrowser    = true,
                PreferencesAllowOriginalDownload = true,
                PreferencesLinkLatestVersion     = true,
                PreferencesNotifyOnVisit         = false,
                PreferencesPasswordRequired      = false
            ));
        }

        if (!toInsert.isEmpty()) {
            List<Id> insertedDistributionIds = new List<Id>();
            Database.SaveResult[] saveResults = Database.insert(toInsert, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    insertedDistributionIds.add(saveResults[i].getId());
                    continue;
                }

                for (Database.Error error : saveResults[i].getErrors()) {
                    System.debug(LoggingLevel.WARN,
                                 'getOrCreatePublicUrls: failed to create ContentDistribution for CV ' +
                                 toInsert[i].ContentVersionId + ': ' + error.getMessage()
                                );
                }
            }

            if (!insertedDistributionIds.isEmpty()) {
                for (ContentDistribution cd : [
                    SELECT Id, ContentVersionId, ContentDownloadUrl, DistributionPublicUrl
                    FROM   ContentDistribution
                    WHERE  Id IN :insertedDistributionIds
                ]) {
                    urlsByVersionId.put(cd.ContentVersionId, preferredPublicUrl(cd));
                }
            }
        }

        return urlsByVersionId;
    }
    
    @TestVisible
    private static String preferredPublicUrl(ContentDistribution cd) {
        return String.isNotBlank(cd.ContentDownloadUrl)
            ? cd.ContentDownloadUrl
            : cd.DistributionPublicUrl;
    }

    @TestVisible
    private static String contentDistributionName(String title) {
        String safeTitle = String.isBlank(title) ? 'Untitled File' : title;
        String name = 'Public Link - ' + safeTitle;
        return name.length() > CONTENT_DISTRIBUTION_NAME_MAX_LENGTH
            ? name.left(CONTENT_DISTRIBUTION_NAME_MAX_LENGTH)
            : name;
    }

    // ── Drive folder resolution ───────────────────────────────────────────────
    @TestVisible
    private static Map<Id, String> getDriveFolderIdsByAccountId(Set<Id> accountIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) return result;
        
        Set<String> accountIdStrings = new Set<String>();
        for (Id aid : accountIds) accountIdStrings.add(String.valueOf(aid));
        
        List<SObject> entityStorages;
        try {
            if (forceDriveFolderPrimaryQueryFailure) {
                throw new QueryException('Forced primary query failure.');
            }
            entityStorages = Database.query(
                'SELECT Id,' +
                ' fra__Entity_Folder_ID__c,' +
                ' fra__File_Store_Record_Id__c,' +
                ' fra__Associated_Record__c,' +
                ' Record_Id__c' +
                ' FROM fra__Entity_Storage__c' +
                ' WHERE fra__Entity_Folder_ID__c != NULL' +
                ' AND (' +
                ' fra__File_Store_Record_Id__c IN :accountIdStrings' +
                ' OR Record_Id__c IN :accountIdStrings' +
                ' OR fra__Associated_Record__c IN :accountIdStrings' +
                ' )'
            );
        } catch (QueryException e) {
            System.debug(LoggingLevel.WARN,
                         'getDriveFolderIdsByAccountId: OR query failed, falling back. ' +
                         e.getMessage()
                        );
            try {
                if (forceDriveFolderFallbackQueryFailure) {
                    throw new QueryException('Forced fallback query failure.');
                }
                entityStorages = Database.query(
                    'SELECT Id,' +
                    ' fra__Entity_Folder_ID__c,' +
                    ' fra__File_Store_Record_Id__c,' +
                    ' Record_Id__c' +
                    ' FROM fra__Entity_Storage__c' +
                    ' WHERE fra__File_Store_Record_Id__c IN :accountIdStrings' +
                    ' OR Record_Id__c IN :accountIdStrings'
                );
            } catch (QueryException e2) {
                System.debug(LoggingLevel.ERROR,
                             'getDriveFolderIdsByAccountId: fallback also failed. ' +
                             e2.getMessage()
                            );
                return result;
            }
        }
        
        mergeEntityStorageFolders(result, accountIds, entityStorages);
        return result;
    }
    
    private static void mergeEntityStorageFolders(
        Map<Id, String> driveFolderIdsByAccountId,
        Set<Id>         accountIds,
        List<SObject>   entityStorages
    ) {
        for (SObject es : entityStorages) {
            String driveFolderId = getStringValue(es, 'fra__Entity_Folder_ID__c');
            if (String.isBlank(driveFolderId)) continue;
            Id accountId = resolveAccountId(es, accountIds);
            if (accountId != null && !driveFolderIdsByAccountId.containsKey(accountId)) {
                driveFolderIdsByAccountId.put(accountId, driveFolderId);
            }
        }
    }
    
    @TestVisible
    private static Id resolveAccountId(SObject es, Set<Id> accountIds) {
        for (String f : new List<String>{
            'fra__File_Store_Record_Id__c',
                'Record_Id__c',
                'fra__Associated_Record__c'
                }) {
                    String val = getStringValue(es, f);
                    if (String.isBlank(val)) continue;
                    try {
                        Id candidateId = (Id) val;
                        if (accountIds.contains(candidateId)) return candidateId;
                    } catch (Exception ex) { }
                }
        return null;
    }
    
    // ── Helpers ───────────────────────────────────────────────────────────────
    private static Integer parseIntParam(
        RestRequest req,
        String      paramName,
        Integer     defaultVal
    ) {
        if (req == null || req.params == null) return defaultVal;
        String raw = req.params.get(paramName);
        if (String.isBlank(raw)) return defaultVal;
        try {
            return Integer.valueOf(raw);
        } catch (Exception e) {
            return defaultVal;
        }
    }

    private static String getStringValue(SObject record, String fieldApiName) {
        Object value = record.get(fieldApiName);
        return value == null ? null : String.valueOf(value);
    }
    
    private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
    
    private class AccountUnsyncedFilesException extends Exception {}
   
    
     global class UnsyncedFilesRequest {
        public Boolean success;
        public Integer totalRecords;
        public Integer processedRecords;
        public Integer successCount;
        public Integer failedCount;
        public List<SuccessfulUpload> successfulUploads;
        public List<Object> failedUploads;
    }

    // Wrapper for each successful uploaded file item.
    global class SuccessfulUpload {
        public String accountId;
        public String contentVersionId;
        public String googleDriveFileId;
        public String googleDriveFolderId;
        public String googleDrivePublicUrl;
        public String fileName;
        public String fileType;
        public Integer fileSize;
        public String status;
    }

    // Wrapper for Salesforce response.
    global class UnsyncedFileResponse {
        public Boolean success;
        public String message;
        public Integer processedRecords;
        public Integer updatedRecords;
        public Integer failedRecords;

        public UnsyncedFileResponse(
            Boolean success,
            String message,
            Integer processedRecords,
            Integer updatedRecords,
            Integer failedRecords
        ) {
            this.success = success;
            this.message = message;
            this.processedRecords = processedRecords;
            this.updatedRecords = updatedRecords;
            this.failedRecords = failedRecords;
        }
    }

    @HttpPost
    global static UnsyncedFileResponse createUnsyncedFiles() {
        try {
            String requestBody = RestContext.request.requestBody.toString();

            // Deserialize new JSON object payload.
            UnsyncedFilesRequest requestData =
                (UnsyncedFilesRequest) JSON.deserialize(
                    requestBody,
                    UnsyncedFilesRequest.class
                );

            List<SuccessfulUpload> uploads = requestData.successfulUploads;

            if (uploads == null || uploads.isEmpty()) {
                return new UnsyncedFileResponse(
                    true,
                    'Upload results received successfully.',
                    requestData != null ? requestData.totalRecords : 0,
                    0,
                    requestData != null && requestData.failedCount != null ? requestData.failedCount : 0
                );
            }

            Set<String> folderIds = new Set<String>();
            Set<String> accountIds = new Set<String>();

            // Collect Folder IDs and Account IDs for bulk query.
            for (SuccessfulUpload upload : uploads) {
                if (String.isNotBlank(upload.googleDriveFolderId)) {
                    folderIds.add(upload.googleDriveFolderId);
                }

                if (String.isNotBlank(upload.accountId)) {
                    accountIds.add(upload.accountId);
                }
            }

            Map<String, fra__Entity_Storage__c> folderIdToEntityStorage =
                new Map<String, fra__Entity_Storage__c>();

            Map<String, fra__Entity_Storage__c> accountIdToEntityStorage =
                new Map<String, fra__Entity_Storage__c>();

            // Query Entity Storage records once using Folder ID or Account ID.
            if (!folderIds.isEmpty() || !accountIds.isEmpty()) {
                for (fra__Entity_Storage__c entityStorage : [
                    SELECT Id,
                           fra__File_Store_Record_Id__c,
                           fra__Entity_Folder_Name__c,
                           fra__Entity_Folder_ID__c
                    FROM fra__Entity_Storage__c
                    WHERE fra__Entity_Folder_ID__c IN :folderIds
                       OR fra__File_Store_Record_Id__c IN :accountIds
                ]) {
                    if (String.isNotBlank(entityStorage.fra__Entity_Folder_ID__c)) {
                        folderIdToEntityStorage.put(
                            entityStorage.fra__Entity_Folder_ID__c,
                            entityStorage
                        );
                    }

                    if (String.isNotBlank(entityStorage.fra__File_Store_Record_Id__c)) {
                        accountIdToEntityStorage.put(
                            entityStorage.fra__File_Store_Record_Id__c,
                            entityStorage
                        );
                    }
                }
            }

            List<fra__File_Storage__c> fileStorageRecords = new List<fra__File_Storage__c>();
            Integer failedRecords = requestData.failedCount == null ? 0 : requestData.failedCount;

            // Build File Storage records and fill required Entity Storage parent field.
            for (SuccessfulUpload upload : uploads) {
                fra__Entity_Storage__c matchedEntityStorage;

                // First match by Google Drive folder ID.
                if (
                    String.isNotBlank(upload.googleDriveFolderId) &&
                    folderIdToEntityStorage.containsKey(upload.googleDriveFolderId)
                ) {
                    matchedEntityStorage =
                        folderIdToEntityStorage.get(upload.googleDriveFolderId);
                }
                // Fallback match by Account ID.
                else if (
                    String.isNotBlank(upload.accountId) &&
                    accountIdToEntityStorage.containsKey(upload.accountId)
                ) {
                    matchedEntityStorage =
                        accountIdToEntityStorage.get(upload.accountId);
                }

                // Required master-detail parent was not found.
                if (matchedEntityStorage == null) {
                    failedRecords++;
                    continue;
                }

                fra__File_Storage__c fileStorage = new fra__File_Storage__c();

                fileStorage.Name = upload.fileName;
                fileStorage.fra__File_Name__c = upload.fileName;
                fileStorage.fra__File_Id__c = upload.googleDriveFileId;
                fileStorage.fra__Internal_File_Id__c = upload.contentVersionId;
                putFileStorageValueIfCreateable(
                    fileStorage,
                    'fra__File_Public_Url__c',
                    upload.googleDrivePublicUrl
                );
                putFileStorageValueIfCreateable(
                    fileStorage,
                    'Public_Url_Chekbox__c',
                    String.isNotBlank(upload.googleDrivePublicUrl)
                );
                putFileStorageValueIfCreateable(
                    fileStorage,
                    'fra__Uploaded_Drive__c',
                    'Google Drive'
                );
                putFileStorageValueIfCreateable(
                    fileStorage,
                    'fra__Object_RecordId__c',
                    upload.accountId
                );
                fileStorage.fra__Entity_Storage__c = matchedEntityStorage.Id;

                fileStorageRecords.add(fileStorage);
            }

            if (!fileStorageRecords.isEmpty()) {
                insert fileStorageRecords;
            }

            return new UnsyncedFileResponse(
                true,
                'Upload results received successfully.',
                requestData.totalRecords,
                fileStorageRecords.size(),
                failedRecords
            );
        } catch (Exception ex) {
            RestContext.response.statusCode = 500;

            return new UnsyncedFileResponse(
                false,
                ex.getMessage(),
                0,
                0,
                0
            );
        }
    }

    private static void putFileStorageValueIfCreateable(
        fra__File_Storage__c fileStorage,
        String fieldName,
        Object value
    ) {
        Map<String, Schema.SObjectField> fields =
            fra__File_Storage__c.SObjectType.getDescribe().fields.getMap();

        if (fields.containsKey(fieldName) &&
            fields.get(fieldName).getDescribe().isCreateable()) {
            fileStorage.put(fieldName, value);
        }
    }
}