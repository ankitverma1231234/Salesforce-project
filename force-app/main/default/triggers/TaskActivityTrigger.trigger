trigger TaskActivityTrigger on Task (after insert) {
 
    Set<Id> recordIds = new Set<Id>();

    for (Task t : Trigger.new) {
        if (t.WhatId != null) {
            recordIds.add(t.WhatId);
        }
    }

    ActivityTimelinePublisher.publishByRecordIds(recordIds);
}