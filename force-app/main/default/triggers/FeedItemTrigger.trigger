trigger FeedItemTrigger on FeedItem (after insert, after update) {

    if (Trigger.isAfter && Trigger.isInsert) {
        FeedItemHandler.handleAfterInsert(Trigger.new);

        Set<Id> feedItemsToProcess = new Set<Id>();
        BatonPortalAPI__c config = BatonPortalAPI__c.getOrgDefaults();
        String portalGuestUsername = config != null ? config.UserName__c : null;

        for (FeedItem feed : [
            SELECT Id, ParentId, CreatedBy.Username
            FROM FeedItem 
            WHERE Id IN :Trigger.new]) {

            if (feed.ParentId != null &&
                String.valueOf(feed.ParentId).startsWith('500')) {
                if (portalGuestUsername != null &&
                    feed.CreatedBy.Username == portalGuestUsername) {
                    continue;
                }

                if (!CaseSalesforceRecord.isDescriptionFeedItem(feed.Id) &&
                    !CaseSalesforceRecord.isCaseDescriptionJustProcessed(feed.ParentId)) {

                    feedItemsToProcess.add(feed.Id);
                }
            }
        }
        if (!feedItemsToProcess.isEmpty()) {
            CaseSalesforceRecord.ensurePublicLinksExist(feedItemsToProcess);
            for (Id feedItemId : feedItemsToProcess) {
                CaseSalesforceRecord.sendChatterDataToThirdParty(feedItemId, 'INSERT');
            }
        }
    }
}