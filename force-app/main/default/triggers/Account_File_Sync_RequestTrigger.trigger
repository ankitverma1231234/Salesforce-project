trigger Account_File_Sync_RequestTrigger on Account_File_Sync_Request__e (after insert) {
    Account_File_Sync_RequestTriggerHandler.handle(Trigger.new); 
}