/**
 * AccountFileEventService
 *
 * Publishes a Platform Event (Account_File_Change__e) whenever files
 * linked to an Account are created or deleted. Call publishEvent() from
 * any trigger or Apex that mutates ContentDocumentLink / ContentDocument.
 *
 * The LWC components subscribe to this event via empApi and auto-refresh.
 */
public with sharing class AccountFileEventService {

    /**
     * Publish a change event for a given Account Id.
     * Call this after insert/delete of files linked to an Account.
     *
     * @param accountId  The Account whose file list changed
     * @param action     'created' | 'deleted' | 'updated'
     */
    public static void publishEvent(Id accountId, String action) {
        if (accountId == null) return;

        Account_File_Change__e evt = new Account_File_Change__e(
            Account_Id__c = accountId,
            Action__c     = action
        );

        Database.SaveResult sr = EventBus.publish(evt);
        if (!sr.isSuccess()) {
            System.debug(LoggingLevel.ERROR,
                'Failed to publish Account_File_Change__e: ' +
                sr.getErrors()[0].getMessage());
        }
    }

    /**
     * Convenience overload — publishes for a list of Account Ids.
     * Useful when bulk-deleting files linked to multiple accounts.
     */
    public static void publishEvents(Set<Id> accountIds, String action) {
        if (accountIds == null || accountIds.isEmpty()) return;

        List<Account_File_Change__e> events = new List<Account_File_Change__e>();
        for (Id accountId : accountIds) {
            events.add(new Account_File_Change__e(
                Account_Id__c = accountId,
                Action__c     = action
            ));
        }
        List<Database.SaveResult> results = EventBus.publish(events);
        for (Database.SaveResult sr : results) {
            if (!sr.isSuccess()) {
                System.debug(LoggingLevel.ERROR,
                    'Failed to publish Account_File_Change__e: ' +
                    sr.getErrors()[0].getMessage());
            }
        }
    }
}