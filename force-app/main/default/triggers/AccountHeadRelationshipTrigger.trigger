trigger AccountHeadRelationshipTrigger on Account_Head_Relationship__c (after insert, after update, after delete) {
    if (AccountAccessApprovalHandler.SKIP) return;

    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.AccountHeadRelationshipTrigger__c) return;

    // ── INSERT ────────────────────────────────────────────────────────
    if (Trigger.isInsert) {
        AccountAccessApprovalHandler.handleAfterInsert(Trigger.new);
    }

    // ── INSERT & UPDATE────────────────────────────────────────────────────────
    if (Trigger.isInsert || Trigger.isUpdate) {
        Set<Id> approvedAccountIds = new Set<Id>();
        for (Account_Head_Relationship__c rec : Trigger.new) {

        if (rec.Member_Account__c != null &&  rec.Authorized_Account_Access__c != null) {
            approvedAccountIds.add(rec.Member_Account__c);
        }
    }
    for (Id accId : approvedAccountIds) {
        SendMetriportDataToPortal.sendFamilyFuture(accId);
    }
}

    // ── DELETE ────────────────────────────────────────────────────────
    if (Trigger.isDelete) {
        for (Account_Head_Relationship__c rec : Trigger.old) {
            if (rec.Member_Account__c != null
                && rec.Authorized_Account_Access__c != null) {
                SendFamilyDeleteToPortal.sendFamilyDeleteFuture(
                    rec.Member_Account__c,
                    rec.Authorized_Account_Access__c
                );
            }
        }
    }
}