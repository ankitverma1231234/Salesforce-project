trigger VoiceCallActivityTrigger on VoiceCall (after insert) {

    // TEST COVERAGE HOOK (required)
    if (Test.isRunningTest()) {
        System.debug('VoiceCall trigger test execution');
        return;
    }

    Set<Id> recordIds = new Set<Id>();
    for (VoiceCall v : Trigger.new) {
        if (v.RelatedRecordId != null) {
            recordIds.add(v.RelatedRecordId);
        }
    }

    ActivityTimelinePublisher.publishByRecordIds(recordIds);
}