public with Sharing class Account_File_Sync_RequestTriggerHandler {
 
    public static void handle(List<Account_File_Sync_Request__e> events) {
        List<String> contentVersionIds = new List<String>();
        List<String> accountIds        = new List<String>();
 
        for (Account_File_Sync_Request__e evt : events) {
            System.debug(LoggingLevel.INFO,
                'Account_File_Sync_RequestTriggerHandler: received event — ' +
                'ContentVersionId=' + evt.Content_Version_Id__c +
                ' AccountId='       + evt.Account_Id__c +
                ' FileType='        + evt.File_Type__c +
                ' DriveFolderId='   + evt.Drive_Folder_Id__c +
                ' PublicUrl='       + evt.Public_Url__c
            );
 
            if (String.isNotBlank(evt.Content_Version_Id__c)) {
                contentVersionIds.add(evt.Content_Version_Id__c);
            }
            if (String.isNotBlank(evt.Account_Id__c)) {
                accountIds.add(evt.Account_Id__c);
            }
        }
 
        System.debug(LoggingLevel.INFO,
            'Account_File_Sync_RequestTriggerHandler: processed ' + events.size() +
            ' events. ContentVersionIds=' + contentVersionIds +
            ' AccountIds=' + accountIds
        );
    }
}