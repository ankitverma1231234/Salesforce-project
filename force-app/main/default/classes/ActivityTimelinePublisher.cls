public class ActivityTimelinePublisher {

    public static void publishByRecordIds(Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) return;

        List<Activity_Timeline_Refresh__e> events = new List<Activity_Timeline_Refresh__e>();

        for (Id rid : recordIds) {
            events.add(new Activity_Timeline_Refresh__e(
                Record_Id__c = rid
            ));
        }

        EventBus.publish(events);
    }
}