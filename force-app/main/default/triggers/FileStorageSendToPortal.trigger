trigger FileStorageSendToPortal on fra__File_Storage__c (after insert, after update, after delete) {
    if (Trigger.isAfter && Trigger.isInsert) {
        Set<Id> fileStorageIdsToSend = new Set<Id>();
        for (fra__File_Storage__c fs : Trigger.new) {
            if (fs.Send_to_Portal__c == true) {
                fileStorageIdsToSend.add(fs.Id);
            }
        }
        if (!fileStorageIdsToSend.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(
                new CDPortalPrepareQueueable(
                    new List<Id>(fileStorageIdsToSend)
                )
            );
        }
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        Set<Id> fileStorageIdsToSend = new Set<Id>();
        Set<Id> fileStorageIdsDeleted = new Set<Id>();
        Set<Id> aiSourceFileIds      = new Set<Id>();

        for (fra__File_Storage__c newFs : Trigger.new) {
            fra__File_Storage__c oldFs = Trigger.oldMap.get(newFs.Id);
            Boolean wasEnabled     = oldFs.Send_to_Portal__c == true;
            Boolean isEnabled      = newFs.Send_to_Portal__c == true;
            Boolean isStillEnabled = wasEnabled && isEnabled;

            Boolean dateChange         = oldFs.Date_of_Service_Display__c != newFs.Date_of_Service_Display__c;
            Boolean description        = oldFs.Description__c            != newFs.Description__c;
            Boolean publicURl          = oldFs.fra__File_Public_Url__c   != newFs.fra__File_Public_Url__c;
            Boolean titleChange        = oldFs.fra__File_Name__c         != newFs.fra__File_Name__c;
            Boolean sourceTypeChange   = oldFs.Source_Type__c            != newFs.Source_Type__c;
            Boolean categoryChange     = oldFs.Category__c               != newFs.Category__c;

            if (
                (isEnabled && !wasEnabled)
                ||
                (isStillEnabled && (dateChange || titleChange || description || sourceTypeChange || categoryChange || publicURl))
                   
            ) {
                fileStorageIdsToSend.add(newFs.Id);
            }
            
            if (wasEnabled && !isEnabled) {
                fileStorageIdsDeleted.add(newFs.Id);
            }

            if (isEnabled && !wasEnabled && newFs.Fra_AI_Source_File_Id__c != null) {
                aiSourceFileIds.add(newFs.Fra_AI_Source_File_Id__c);
            }
        }

        if (!aiSourceFileIds.isEmpty()) {
            List<fra__File_Storage__c> aiRelatedFiles = [
                SELECT Id, Send_to_Portal__c
                FROM fra__File_Storage__c
                WHERE Fra_AI_Source_File_Id__c IN :aiSourceFileIds
                AND   Fra_AI_Source_File_Id__c != null
            ];
            for (fra__File_Storage__c fs : aiRelatedFiles) {
                fs.Send_to_Portal__c = true;
            }
            if (!aiRelatedFiles.isEmpty()) {
                System.debug('Updating AI related records: ' + aiRelatedFiles.size());
                update aiRelatedFiles;
            }
        }

        if (!fileStorageIdsToSend.isEmpty()) {
            System.enqueueJob(
                new CDPortalPrepareQueueable(
                    new List<Id>(fileStorageIdsToSend)
                )
            );
        }
        
       if (!fileStorageIdsDeleted.isEmpty() && !Test.isRunningTest()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(
                fileStorageIdsDeleted, 'fra__File_Storage__c'
            );
        }
    }

    if (Trigger.isAfter && Trigger.isDelete) {
        Set<Id> fileStorageIdsDeleted = new Set<Id>();
        for (fra__File_Storage__c fs : Trigger.old) {
            if (fs.Send_to_Portal__c == true) {
                fileStorageIdsDeleted.add(fs.Id);
            }
        }
        if (!fileStorageIdsDeleted.isEmpty() && !Test.isRunningTest()) {
            MedicalSalesforceDeleteRecord.deleteRecordFromThirdParty(
                fileStorageIdsDeleted, 'fra__File_Storage__c'
            );
        }
    }
}