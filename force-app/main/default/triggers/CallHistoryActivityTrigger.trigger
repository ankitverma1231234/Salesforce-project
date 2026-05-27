trigger CallHistoryActivityTrigger on ccra__Call_History__c (after insert,after update) {
    System.debug('CallHistoryActivityTrigger fired for ' + Trigger.new.size() + ' records');
    List<Activity_Timeline_Refresh__e> events = new List<Activity_Timeline_Refresh__e>();
    for (ccra__Call_History__c ch : Trigger.new) {
        System.debug('Processing Call History - Account: ' + ch.ccra__Account__c);
        if (ch.ccra__Account__c != null) {
            events.add(new Activity_Timeline_Refresh__e(
                Record_Id__c = ch.ccra__Account__c
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