trigger EmailActivityTrigger on EmailMessage (after insert) {
System.debug('CallHistoryActivityTrigger fired for ' + Trigger.new.size() + ' records');
    List<Activity_Timeline_Refresh__e> events = new List<Activity_Timeline_Refresh__e>();
    for (EmailMessage em : Trigger.new) {
        System.debug('Processing Call History - Account: ' + em.RelatedToId);
        if (em.RelatedToId != null) {
            events.add(new Activity_Timeline_Refresh__e(
                Record_Id__c = em.RelatedToId
            ));
        }
    }
    if (!events.isEmpty()) {
        List<Database.SaveResult> results = EventBus.publish(events);
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                System.debug('Platform Event published successfully');
            } else {
                for (Database.Error err : result.getErrors()) {
                    System.debug('Error publishing event: ' + err.getMessage());
                }
            }
        }
    }
}