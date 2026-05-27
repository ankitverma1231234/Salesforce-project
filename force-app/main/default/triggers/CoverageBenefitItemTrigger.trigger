trigger CoverageBenefitItemTrigger on CoverageBenefitItem (after insert, after update) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if(triggerSettings == null || !triggerSettings.CoverageBenefitItem__c){
        return;
    }
    
    Set<Id> changedCoverageBenefitItemIds = new Set<Id>();
    
    for (CoverageBenefitItem cbItem : Trigger.new) {
        changedCoverageBenefitItemIds.add(cbItem.Id); 
    }
    
    if (!changedCoverageBenefitItemIds.isEmpty()) {
        MemberPlanCalloutFuture.sendForCoverageBenefitItems(
            new List<Id>(changedCoverageBenefitItemIds)
        );
    }
    
}