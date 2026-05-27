trigger CoverageBenefitTrigger on CoverageBenefit (after insert, after update) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if(triggerSettings == null || !triggerSettings.CoverageBenefit__c){
        return;
    }
    
    Set<Id> changedCoverageBenefitIds = new Set<Id>();
    
    for (CoverageBenefit cb : Trigger.new) {
        changedCoverageBenefitIds.add(cb.Id);  
    }
    
    if (!changedCoverageBenefitIds.isEmpty()) {
        MemberPlanCalloutFuture.sendForCoverageBenefits(
            new List<Id>(changedCoverageBenefitIds)
        );
    }
}