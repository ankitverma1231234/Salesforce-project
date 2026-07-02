trigger AccountHeadRelationshipTrigger on Account_Head_Relationship__c (after insert, after update, after delete) {
    if (AccountAccessApprovalHandler.SKIP) return;
    
    TriggerSettings__c triggerSettings = TriggerSettings__c.getInstance();
    if (triggerSettings == null || !triggerSettings.AccountHeadRelationshipTrigger__c) return;
   
    Set<Id> guestAccountIds = new Set<Id>();
    if (Trigger.isInsert || Trigger.isUpdate) {
        Set<Id> memberAccountIds = new Set<Id>();
        for (Account_Head_Relationship__c ahr : Trigger.new) {
            if (ahr.Member_Account__c != null) {
                memberAccountIds.add(ahr.Member_Account__c);
            }
        }
        if (!memberAccountIds.isEmpty()) {
            for (Account acc : [
                SELECT Id FROM Account
                WHERE Id IN :memberAccountIds
                AND Is_Guest__c = true
            ]) {
                guestAccountIds.add(acc.Id);
            }
        }
    }
    
    // ── INSERT ────────────────────────────────────────────────────────
    if (Trigger.isInsert) {
        AccountAccessApprovalHandler.handleAfterInsert(Trigger.new);
        
        if (!guestAccountIds.isEmpty()) {
            GuestAccountHeadRelationship.sendGuestPayloadToPortal(guestAccountIds);
        }
    }
    
    // ── INSERT & UPDATE ──────────────────────────────────────────────
    if (Trigger.isInsert || Trigger.isUpdate) {
        Set<Id> approvedAccountIds = new Set<Id>();
        for (Account_Head_Relationship__c rec : Trigger.new) {
            if (rec.Member_Account__c != null && rec.Authorized_Account_Access__c != null) {
                approvedAccountIds.add(rec.Member_Account__c);
            }
        }
        approvedAccountIds.removeAll(guestAccountIds);
        
        for (Id accId : approvedAccountIds) {
            SendMetriportDataToPortal.sendFamilyFuture(accId);
        }
    }
    
    // ── DELETE ────────────────────────────────────────────────────────
    if (Trigger.isDelete) {
        for (Account_Head_Relationship__c ahr : Trigger.old) {
            if (ahr.Member_Account__c != null && ahr.Authorized_Account_Access__c != null) {
                SendFamilyDeleteToPortal.sendFamilyDeleteFuture(
                    ahr.Member_Account__c,             
                    ahr.Authorized_Account_Access__c,  
                    ahr.Id                         
                );
            }
        }
    }
}