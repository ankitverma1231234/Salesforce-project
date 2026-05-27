trigger EfaxTrigger on smsefax_guru__eFAX__c (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        EfaxTriggerHandler.onBeforeInsert(Trigger.new);
    }
}