trigger CoverageBenefitItemDetailTrigger on medicalcoverage__CoverageBenefitItemDetail__c (after insert, after update) {
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if(triggerSettings == null || !triggerSettings.CoverageBenefitItemDetail__c){
        return;
    }
    Set<Id> changedDetailIds = new Set<Id>();
    for (medicalcoverage__CoverageBenefitItemDetail__c detail : Trigger.new) {
        changedDetailIds.add(detail.Id);
    }
    if (!changedDetailIds.isEmpty()) {
        MemberPlanCalloutFuture.sendForCoverageBenefitItemDetails(
            new List<Id>(changedDetailIds)
        );
    }
}