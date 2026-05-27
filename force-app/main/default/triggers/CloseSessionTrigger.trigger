trigger CloseSessionTrigger on Message_Session__c (after Update) {
    if(trigger.isAfter && trigger.isUpdate){
        MessageCloseSessionHandler.UpdateStatus(Trigger.new, Trigger.oldMap);
    }    
}