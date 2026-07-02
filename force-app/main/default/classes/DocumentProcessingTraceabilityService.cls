public without sharing class DocumentProcessingTraceabilityService {
    @TestVisible
    private static Boolean isLinkingFileStorage = false;

    public static void linkAiSummaryToProcessingLog(
        Id sourceContentDocumentId,
        Id aiContentVersionId,
        Id aiContentDocumentId
    ) {
        System.debug(LoggingLevel.DEBUG,
            'DocumentProcessingTraceabilityService.linkAiSummaryToProcessingLog started. sourceContentDocumentId=' +
            sourceContentDocumentId + ', aiContentVersionId=' + aiContentVersionId +
            ', aiContentDocumentId=' + aiContentDocumentId
        );

        if (sourceContentDocumentId == null || aiContentVersionId == null || aiContentDocumentId == null) {
            System.debug(LoggingLevel.WARN, 'Skipping AI summary traceability because one or more ids are blank.');
            return;
        }

        try {
            List<ContentVersion> mainVersions = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId = :sourceContentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];

            if (mainVersions.isEmpty()) {
                System.debug(LoggingLevel.WARN,
                    'Skipping AI summary traceability because no latest source ContentVersion was found. ContentDocumentId=' +
                    sourceContentDocumentId
                );
                return;
            }

            List<Document_Processing_Log__c> logs = [
                SELECT Id
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c = :String.valueOf(mainVersions[0].Id)
                LIMIT 1
            ];

            if (logs.isEmpty()) {
                System.debug(LoggingLevel.WARN,
                    'Skipping AI summary traceability because no Document Processing Log was found for ContentVersionId=' +
                    mainVersions[0].Id
                );
                return;
            }

            Document_Processing_Log__c logUpdate = new Document_Processing_Log__c(
                Id = logs[0].Id,
                Main_Content_Document_Id__c = String.valueOf(sourceContentDocumentId),
                AI_Summary_Content_Version_Id__c = String.valueOf(aiContentVersionId),
                AI_Summary_Content_Document_Id__c = String.valueOf(aiContentDocumentId)
            );
            update logUpdate;

            System.debug(LoggingLevel.DEBUG,
                'Updated Document Processing Log with AI summary traceability. LogId=' + logs[0].Id
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'Failed to link AI summary traceability: ' + ex.getMessage() + '\n' + ex.getStackTraceString()
            );
        }
    }

    public static void linkFileStorageRecords(List<fra__File_Storage__c> triggerRecords) {
        System.debug(LoggingLevel.DEBUG,
            'DocumentProcessingTraceabilityService.linkFileStorageRecords started. Size=' +
            (triggerRecords == null ? 0 : triggerRecords.size())
        );

        if (isLinkingFileStorage) {
            System.debug(LoggingLevel.DEBUG, 'Skipping file storage traceability because recursion guard is active.');
            return;
        }
        if (triggerRecords == null || triggerRecords.isEmpty()) {
            return;
        }

        isLinkingFileStorage = true;
        try {
            Set<Id> fileStorageIds = new Set<Id>();
            for (fra__File_Storage__c record : triggerRecords) {
                if (record != null && record.Id != null) {
                    fileStorageIds.add(record.Id);
                }
            }
            if (fileStorageIds.isEmpty()) {
                return;
            }

            List<fra__File_Storage__c> fileStorages = [
                SELECT Id, Name, fra__Uploaded_Drive__c, fra__Object_RecordId__c
                FROM fra__File_Storage__c
                WHERE Id IN :fileStorageIds
            ];

            Map<Id, fra__File_Storage__c> eligibleFileStorages = new Map<Id, fra__File_Storage__c>();
            Set<String> fileNames = new Set<String>();
            for (fra__File_Storage__c fileStorage : fileStorages) {
                if (!isGoogleDriveRecord(fileStorage)) {
                    System.debug(LoggingLevel.DEBUG,
                        'Skipping File Storage traceability because Uploaded Drive is not Google Drive. FileStorageId=' +
                        fileStorage.Id
                    );
                    continue;
                }
                if (String.isBlank(fileStorage.Name)) {
                    System.debug(LoggingLevel.DEBUG,
                        'Skipping File Storage traceability because Name is blank. FileStorageId=' + fileStorage.Id
                    );
                    continue;
                }

                eligibleFileStorages.put(fileStorage.Id, fileStorage);
                fileNames.add(fileStorage.Name);
            }

            if (eligibleFileStorages.isEmpty() || fileNames.isEmpty()) {
                System.debug(LoggingLevel.DEBUG, 'No eligible Google Drive File Storage records found for traceability.');
                return;
            }

            List<ContentVersion> candidateVersions = [
                SELECT Id, ContentDocumentId, Title, PathOnClient, Source_Type__c, Related_File__c, FirstPublishLocationId
                FROM ContentVersion
                WHERE IsLatest = true
                AND (Title IN :fileNames OR PathOnClient IN :fileNames)
            ];

            Map<String, List<ContentVersion>> candidatesByName = new Map<String, List<ContentVersion>>();
            for (ContentVersion candidate : candidateVersions) {
                addCandidate(candidatesByName, candidate.Title, candidate);
                addCandidate(candidatesByName, candidate.PathOnClient, candidate);
            }

            Map<Id, ContentVersion> matchedByFileStorageId = new Map<Id, ContentVersion>();
            Set<Id> mainContentVersionIds = new Set<Id>();
            Set<Id> aiRelatedMainContentDocumentIds = new Set<Id>();

            for (fra__File_Storage__c fileStorage : eligibleFileStorages.values()) {
                ContentVersion matchedVersion = findSingleMatch(fileStorage, candidatesByName.get(fileStorage.Name));
                if (matchedVersion == null) {
                    System.debug(LoggingLevel.WARN,
                        'No unambiguous ContentVersion match found for File Storage. FileStorageId=' +
                        fileStorage.Id + ', Name=' + fileStorage.Name
                    );
                    continue;
                }

                matchedByFileStorageId.put(fileStorage.Id, matchedVersion);
                if (isMetriportSource(matchedVersion.Source_Type__c)) {
                    mainContentVersionIds.add(matchedVersion.Id);
                } else if (isAiSource(matchedVersion.Source_Type__c) && matchedVersion.Related_File__c != null) {
                    aiRelatedMainContentDocumentIds.add(matchedVersion.Related_File__c);
                } else {
                    System.debug(LoggingLevel.DEBUG,
                        'Matched ContentVersion ignored because Source_Type__c is not Metriport or AI. FileStorageId=' +
                        fileStorage.Id + ', ContentVersionId=' + matchedVersion.Id +
                        ', Source=' + matchedVersion.Source_Type__c
                    );
                }
            }

            Map<Id, ContentVersion> latestMainVersionByDocumentId = new Map<Id, ContentVersion>();
            if (!aiRelatedMainContentDocumentIds.isEmpty()) {
                for (ContentVersion mainVersion : [
                    SELECT Id, ContentDocumentId
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :aiRelatedMainContentDocumentIds
                    AND IsLatest = true
                ]) {
                    latestMainVersionByDocumentId.put(mainVersion.ContentDocumentId, mainVersion);
                    mainContentVersionIds.add(mainVersion.Id);
                }
            }

            if (mainContentVersionIds.isEmpty()) {
                System.debug(LoggingLevel.DEBUG, 'No main ContentVersion ids were identified for log updates.');
                return;
            }

            Map<Id, Document_Processing_Log__c> logByMainContentVersionId = new Map<Id, Document_Processing_Log__c>();
            for (Document_Processing_Log__c logRecord : [
                SELECT Id,
                       Content_Version_Id__c,
                       Main_File_Storage_Record_Id__c,
                       AI_Summary_File_Storage_Record_Id__c
                FROM Document_Processing_Log__c
                WHERE Content_Version_Id__c IN :toStringSet(mainContentVersionIds)
            ]) {
                logByMainContentVersionId.put((Id) logRecord.Content_Version_Id__c, logRecord);
            }

            Map<Id, Document_Processing_Log__c> updatesByLogId = new Map<Id, Document_Processing_Log__c>();
            Datetime completedOn = System.now();

            for (Id fileStorageId : matchedByFileStorageId.keySet()) {
                ContentVersion matchedVersion = matchedByFileStorageId.get(fileStorageId);

                if (isMetriportSource(matchedVersion.Source_Type__c)) {
                    Document_Processing_Log__c existingLog = logByMainContentVersionId.get(matchedVersion.Id);
                    if (existingLog == null) {
                        System.debug(LoggingLevel.WARN,
                            'No Document Processing Log found for main ContentVersion. ContentVersionId=' +
                            matchedVersion.Id + ', FileStorageId=' + fileStorageId
                        );
                        continue;
                    }

                    Document_Processing_Log__c logUpdate = getOrCreateLogUpdate(updatesByLogId, existingLog.Id);
                    logUpdate.Main_Content_Document_Id__c = String.valueOf(matchedVersion.ContentDocumentId);
                    logUpdate.Main_File_Storage_Record_Id__c = String.valueOf(fileStorageId);
                } else if (isAiSource(matchedVersion.Source_Type__c) && matchedVersion.Related_File__c != null) {
                    ContentVersion mainVersion = latestMainVersionByDocumentId.get(matchedVersion.Related_File__c);
                    if (mainVersion == null) {
                        System.debug(LoggingLevel.WARN,
                            'No main ContentVersion found for AI summary Related_File__c. RelatedFile=' +
                            matchedVersion.Related_File__c + ', FileStorageId=' + fileStorageId
                        );
                        continue;
                    }

                    Document_Processing_Log__c existingLog = logByMainContentVersionId.get(mainVersion.Id);
                    if (existingLog == null) {
                        System.debug(LoggingLevel.WARN,
                            'No Document Processing Log found for AI summary main ContentVersion. MainContentVersionId=' +
                            mainVersion.Id + ', FileStorageId=' + fileStorageId
                        );
                        continue;
                    }

                    Document_Processing_Log__c logUpdate = getOrCreateLogUpdate(updatesByLogId, existingLog.Id);
                    logUpdate.AI_Summary_Content_Version_Id__c = String.valueOf(matchedVersion.Id);
                    logUpdate.AI_Summary_Content_Document_Id__c = String.valueOf(matchedVersion.ContentDocumentId);
                    logUpdate.AI_Summary_File_Storage_Record_Id__c = String.valueOf(fileStorageId);
                }
            }

            for (Id mainVersionId : logByMainContentVersionId.keySet()) {
                Document_Processing_Log__c existingLog = logByMainContentVersionId.get(mainVersionId);
                Document_Processing_Log__c pendingUpdate = updatesByLogId.get(existingLog.Id);
                if (pendingUpdate == null) {
                    continue;
                }

                Boolean hasMainUpload = String.isNotBlank(pendingUpdate.Main_File_Storage_Record_Id__c)
                    || String.isNotBlank(existingLog.Main_File_Storage_Record_Id__c);
                Boolean hasAiUpload = String.isNotBlank(pendingUpdate.AI_Summary_File_Storage_Record_Id__c)
                    || String.isNotBlank(existingLog.AI_Summary_File_Storage_Record_Id__c);

                if (hasMainUpload && hasAiUpload) {
                    pendingUpdate.Drive_Sync_Completed_On__c = completedOn;
                    pendingUpdate.Current_Status__c = 'Google Drive Synced';
                }
            }

            if (updatesByLogId.isEmpty()) {
                System.debug(LoggingLevel.DEBUG, 'No Document Processing Log updates were generated for File Storage traceability.');
                return;
            }

            Database.SaveResult[] results = Database.update(updatesByLogId.values(), false);
            Integer index = 0;
            for (Database.SaveResult result : results) {
                Document_Processing_Log__c attemptedUpdate = updatesByLogId.values()[index];
                if (!result.isSuccess()) {
                    for (Database.Error error : result.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'Failed to update Document Processing Log traceability. LogId=' +
                            attemptedUpdate.Id + ', Error=' + error.getMessage()
                        );
                    }
                } else {
                    System.debug(LoggingLevel.DEBUG,
                        'Updated Document Processing Log File Storage traceability. LogId=' + attemptedUpdate.Id
                    );
                }
                index++;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'Failed to link File Storage traceability: ' + ex.getMessage() + '\n' + ex.getStackTraceString()
            );
        } finally {
            isLinkingFileStorage = false;
        }
    }

    private static Boolean isGoogleDriveRecord(fra__File_Storage__c fileStorage) {
        return fileStorage != null &&
            String.isNotBlank(fileStorage.fra__Uploaded_Drive__c) &&
            fileStorage.fra__Uploaded_Drive__c.equalsIgnoreCase('Google Drive');
    }

    private static void addCandidate(
        Map<String, List<ContentVersion>> candidatesByName,
        String key,
        ContentVersion candidate
    ) {
        if (String.isBlank(key) || candidate == null) {
            return;
        }
        if (!candidatesByName.containsKey(key)) {
            candidatesByName.put(key, new List<ContentVersion>());
        }
        if (!candidatesByName.get(key).contains(candidate)) {
            candidatesByName.get(key).add(candidate);
        }
    }

    private static ContentVersion findSingleMatch(
        fra__File_Storage__c fileStorage,
        List<ContentVersion> candidates
    ) {
        if (fileStorage == null || candidates == null || candidates.isEmpty()) {
            return null;
        }

        Id parentId = parseId(fileStorage.fra__Object_RecordId__c);
        if (parentId != null) {
            List<ContentVersion> sameParentCandidates = new List<ContentVersion>();
            for (ContentVersion candidate : candidates) {
                if (candidate.FirstPublishLocationId == parentId) {
                    sameParentCandidates.add(candidate);
                }
            }
            if (sameParentCandidates.size() == 1) {
                return sameParentCandidates[0];
            }
            if (sameParentCandidates.size() > 1) {
                return null;
            }
        }

        return candidates.size() == 1 ? candidates[0] : null;
    }

    private static Id parseId(String possibleId) {
        if (String.isBlank(possibleId)) {
            return null;
        }
        try {
            return (Id) possibleId;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean isMetriportSource(String source) {
        return String.isNotBlank(source) && source.equalsIgnoreCase('Metriport');
    }

    private static Boolean isAiSource(String source) {
        return String.isNotBlank(source) && source.equalsIgnoreCase('AI');
    }

    private static Set<String> toStringSet(Set<Id> ids) {
        Set<String> values = new Set<String>();
        for (Id recordId : ids) {
            values.add(String.valueOf(recordId));
        }
        return values;
    }

    private static Document_Processing_Log__c getOrCreateLogUpdate(
        Map<Id, Document_Processing_Log__c> updatesByLogId,
        Id logId
    ) {
        if (!updatesByLogId.containsKey(logId)) {
            updatesByLogId.put(logId, new Document_Processing_Log__c(Id = logId));
        }
        return updatesByLogId.get(logId);
    }
}