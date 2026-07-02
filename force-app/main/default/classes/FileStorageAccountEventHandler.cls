public without sharing class FileStorageAccountEventHandler {

    public static void handleAfterInsert(List<fra__File_Storage__c> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        // Collect ContentVersion IDs from fra__Internal_File_Id__c
        Set<Id> contentVersionIds = new Set<Id>();
        for (fra__File_Storage__c record : newRecords) {
            try {
                Object fieldValue = record.get('fra__Internal_File_Id__c');
                if (fieldValue == null) continue;
                String idStr = String.valueOf(fieldValue).trim();
                if (String.isBlank(idStr) || idStr.length() < 15) continue;
                contentVersionIds.add(Id.valueOf(idStr));
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN,
                    'FileStorageAccountEventHandler: skipping record ' + record.Id +
                    ' — ' + ex.getMessage());
            }
        }

        if (contentVersionIds.isEmpty()) {
            return;
        }

        // ContentVersion → ContentDocumentId
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentVersion cv : [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :contentVersionIds
        ]) {
            contentDocumentIds.add(cv.ContentDocumentId);
        }

        if (contentDocumentIds.isEmpty()) {
            return;
        }

        // ContentDocumentLink → Account
        Set<Id> accountIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :contentDocumentIds
        ]) {
            try {
                Id linkedId = cdl.LinkedEntityId;
                if (linkedId != null && linkedId.getSObjectType() == Account.SObjectType) {
                    accountIds.add(linkedId);
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN,
                    'FileStorageAccountEventHandler: skipping CDL ' + cdl.Id +
                    ' — ' + ex.getMessage());
            }
        }

        if (!accountIds.isEmpty()) {
            AccountFileEventService.publishEvents(accountIds, 'created');
        }
    }
}