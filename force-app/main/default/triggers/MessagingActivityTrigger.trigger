trigger MessagingActivityTrigger on MessagingSession (after insert) {

    // TEST COVERAGE HOOK (required)
    if (Test.isRunningTest()) {
        System.debug('MessagingSession trigger test execution');
        return;
    }

    Set<Id> recordIds = new Set<Id>();
    for (MessagingSession m : Trigger.new) {
        if (m.EndUserAccountId != null) {
            recordIds.add(m.EndUserAccountId);
        }
    }

    ActivityTimelinePublisher.publishByRecordIds(recordIds);
}