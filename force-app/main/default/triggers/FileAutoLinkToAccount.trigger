trigger FileAutoLinkToAccount on ContentDocumentLink (after insert) {

    Set<Id> messageHistoryIds = new Set<Id>();
    Set<Id> emailLogIds = new Set<Id>(); 
    Set<Id> efaxIds = new Set<Id>();
    Set<Id> caseIds = new Set<Id>();

    for(ContentDocumentLink cdl : Trigger.new) {

        SObjectType linkedType = cdl.LinkedEntityId.getSObjectType();

        if(linkedType == sra__Message_History__c.SObjectType) {
            messageHistoryIds.add(cdl.LinkedEntityId);
        }
        else if(linkedType == Email_Log__c.SObjectType) {
            emailLogIds.add(cdl.LinkedEntityId);
        }
       /* else if(linkedType == smsefax_guru__eFAX__c.SObjectType) {
            efaxIds.add(cdl.LinkedEntityId);
        } */
        else if(linkedType == Case.SObjectType) {
            caseIds.add(cdl.LinkedEntityId);
        }
    }

    // Map<RecordId, AccountId>
    Map<Id, Id> recordToAccountMap = new Map<Id, Id>();

    // Message History
    if(!messageHistoryIds.isEmpty()) {
        for(sra__Message_History__c rec : [
            SELECT Id, sra__Related_Object_Id__c
            FROM sra__Message_History__c
            WHERE Id IN :messageHistoryIds
        ]) {
            if(rec.sra__Related_Object_Id__c != null) {
                recordToAccountMap.put(rec.Id, rec.sra__Related_Object_Id__c);
            }
        }
    }

    // Email Log
    if(!emailLogIds.isEmpty()) {
        for(Email_Log__c rec : [
            SELECT Id, Account__c
            FROM Email_Log__c
            WHERE Id IN :emailLogIds
        ]) {
            if(rec.Account__c != null) {
                recordToAccountMap.put(rec.Id, rec.Account__c);
            }
        }
    }

    // eFAX
    /*if(!efaxIds.isEmpty()) {
        for(smsefax_guru__eFAX__c rec : [
            SELECT Id, smsefax_guru__Account__c
            FROM smsefax_guru__eFAX__c
            WHERE Id IN :efaxIds
        ]) {
            if(rec.smsefax_guru__Account__c != null) {
                recordToAccountMap.put(rec.Id, rec.smsefax_guru__Account__c);
            }
        }
    } */

    // Case (NEW)
    if(!caseIds.isEmpty()) {
        for(Case c : [
            SELECT Id, AccountId
            FROM Case
            WHERE Id IN :caseIds
        ]) {
            if(c.AccountId != null) {
                recordToAccountMap.put(c.Id, c.AccountId);
            }
        }
    }

    if(recordToAccountMap.isEmpty()) return;

    Set<Id> accountIds = new Set<Id>(recordToAccountMap.values());

    // Collect ContentDocumentIds from Trigger
    Set<Id> contentDocIds = new Set<Id>();
    for(ContentDocumentLink cdl : Trigger.new) {
        contentDocIds.add(cdl.ContentDocumentId);
    }

    // Proper duplicate prevention
    Set<String> existingKeys = new Set<String>();

    for(ContentDocumentLink existing : [
        SELECT ContentDocumentId, LinkedEntityId
        FROM ContentDocumentLink
        WHERE LinkedEntityId IN :accountIds
        AND ContentDocumentId IN :contentDocIds
    ]) {
        existingKeys.add(existing.ContentDocumentId + '-' + existing.LinkedEntityId);
    }

    List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();

    for(ContentDocumentLink cdl : Trigger.new) {

        Id accountId = recordToAccountMap.get(cdl.LinkedEntityId);

        if(accountId != null) {

            String key = cdl.ContentDocumentId + '-' + accountId;

            if(!existingKeys.contains(key)) {

                newLinks.add(new ContentDocumentLink(
                    ContentDocumentId = cdl.ContentDocumentId,
                    LinkedEntityId = accountId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));

                // Prevent duplicates in same transaction
                existingKeys.add(key);
            }
        }
    }

    if(!newLinks.isEmpty()) {
        insert newLinks;
    }
}