public class VoiceCallActivityHandler {
    
    public static void handleAfterInsert(List<VoiceCall> newVoiceCalls) {
        System.debug('VoiceCallActivityHandler processing ' + newVoiceCalls.size() + ' records');
        
        List<Activity_Timeline_Refresh__e> events = new List<Activity_Timeline_Refresh__e>();
        
        for (VoiceCall va : newVoiceCalls) {
            System.debug('Processing Voice Call - RelatedRecord: ' + va.RelatedRecordId);
            if (va.RelatedRecordId != null) {
                events.add(new Activity_Timeline_Refresh__e(
                    Record_Id__c = va.RelatedRecordId
                ));
            }
        }
        
        if (!events.isEmpty()) {
            publishEvents(events);
        }
    }
    
    @TestVisible
    private static void publishEvents(List<Activity_Timeline_Refresh__e> events) {
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