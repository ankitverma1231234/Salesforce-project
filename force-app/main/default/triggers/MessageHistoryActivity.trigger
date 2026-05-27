trigger MessageHistoryActivity on sra__Message_History__c (after insert,after update) {
    System.debug('MessageHistoryActivity trigger fired for ' + Trigger.new.size() + ' records');
    List<Activity_Timeline_Refresh__e> events = new List<Activity_Timeline_Refresh__e>();
    for (sra__Message_History__c mh : Trigger.new) {
        System.debug('Processing Message History - Account: ' + mh.sra__Account__c);
        if (mh.sra__Account__c != null) {
            events.add(new Activity_Timeline_Refresh__e(
                Record_Id__c = mh.sra__Account__c
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