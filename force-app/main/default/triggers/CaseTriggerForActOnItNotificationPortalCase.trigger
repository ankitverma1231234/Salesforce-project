trigger CaseTriggerForActOnItNotificationPortalCase on Case (after insert) {
    
    CasePortalUserTriggerSettig__c cs = CasePortalUserTriggerSettig__c.getInstance();
    
    if (cs == null || !cs.Execute_Trigger__c || String.isBlank(cs.UserId__c)) {
        return;
    }
    
    List<Case_Auto_Create_Event__e> events = new List<Case_Auto_Create_Event__e>();
    for (Case c : Trigger.new) {
        if (c.CreatedById == cs.UserId__c) {
            events.add(new Case_Auto_Create_Event__e(
                Source_Case_Id__c = c.Id
            ));
        }
    }
    if (!events.isEmpty()) {
        EventBus.publish(events);
    }
}