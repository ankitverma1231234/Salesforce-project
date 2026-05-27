trigger EventActivityTrigger on Event (after insert) {

    Set<Id> recordIds = new Set<Id>();

    for (Event e : Trigger.new) {
        if (e.WhatId != null) {
            recordIds.add(e.WhatId);
        }
    }

    ActivityTimelinePublisher.publishByRecordIds(recordIds);
}