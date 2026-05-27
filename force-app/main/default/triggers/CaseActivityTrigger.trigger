trigger CaseActivityTrigger on Case (after insert) {
System.debug('CallHistoryActivityTrigger fired for ' + Trigger.new.size() + ' records');
    List<Activity_Timeline_Refresh__e> events = new List<Activity_Timeline_Refresh__e>();
    for (Case ca : Trigger.new) {
        System.debug('Processing Call History - Account: ' + ca.AccountId);
        if (ca.AccountId != null) {
            events.add(new Activity_Timeline_Refresh__e(
                Record_Id__c = ca.AccountId
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