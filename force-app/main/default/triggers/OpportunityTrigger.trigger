trigger OpportunityTrigger on Opportunity (after update) {
    OpportunityTriggerHandler.handle(Trigger.newMap, Trigger.oldMap);
}