trigger CaseAutoCreateSubscriberPortalCase on Case_Auto_Create_Event__e (after insert) {
Set<Id> caseIds = new Set<Id>();

    for (Case_Auto_Create_Event__e evt : Trigger.new) {
        if (evt.Source_Case_Id__c != null) {
            caseIds.add((Id)evt.Source_Case_Id__c);
        }
    }

    if (!caseIds.isEmpty()) {
        System.enqueueJob(new CaseAutoCreateQueueablePortalUserActOnIt(caseIds));
    }
}