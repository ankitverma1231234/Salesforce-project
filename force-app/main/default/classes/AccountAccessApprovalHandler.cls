public without sharing class AccountAccessApprovalHandler {
    
    public static Boolean SKIP = false;
    
    public static void handleAfterInsert(List<Account_head_relationship__c> newList) {
        List<Account_head_relationship__c> toStamp = new List<Account_head_relationship__c>();
        for (Account_head_relationship__c r : newList) {
            if (isQualifying(r) && String.isBlank(r.Approval_Token__c)) {
                toStamp.add(r);
            }
        }
        stampAndSend(toStamp);
    }
    
    /*public static void handleAfterUpdate(List<Account_head_relationship__c> newList,
Map<Id, Account_head_relationship__c> oldMap) {
List<Account_head_relationship__c> toStamp = new List<Account_head_relationship__c>();
for (Account_head_relationship__c r : newList) {
Account_head_relationship__c prev = oldMap.get(r.Id);
Boolean nowQualifies = isQualifying(r);
Boolean wasQualifying = prev != null && isQualifying(prev) && String.isNotBlank(prev.Approval_Token__c);
if (nowQualifies && !wasQualifying && String.isBlank(r.Approval_Token__c)) {
toStamp.add(r);
}
}
stampAndSend(toStamp);
}*/
    
    private static Boolean isQualifying(Account_head_relationship__c r) {
        return r.Member_Account__c != null && r.Authorized_Account_Access__c != null;
    }
    
    private static void stampAndSend(List<Account_head_relationship__c> targets) {
        if (targets.isEmpty()) {
            return;
        }
        
        Datetime expiry = Datetime.now().addDays(Integer.valueOf(Label.Token_All_Days));
        List<Account_head_relationship__c> updates = new List<Account_head_relationship__c>();
        Set<Id> idsToEmail = new Set<Id>();
        
        for (Account_head_relationship__c r : targets) {
            Account_head_relationship__c u = new Account_head_relationship__c(
                Id = r.Id,
                Approval_Token__c = AccountAccessTokenUtil.generateToken(),
                Verification_Code__c = AccountAccessTokenUtil.generateVerificationCode(),
                Token_Expiry__c = expiry,
                Portal_Access_Status__c = 'Pending'
            );
            updates.add(u);
            idsToEmail.add(r.Id);
        }
        SKIP = true;
        try {
            update updates;
        } finally {
            SKIP = false;
        }
        
        if (!idsToEmail.isEmpty() && !Test.isRunningTest()) {
            AccountAccessEmailQueueable.sendEmails(idsToEmail);
            MemberAccessNotification.sendEmails(idsToEmail);
            AccountHeadRelationshipSmsQueueable.sendSms(idsToEmail);
            
        } else if (!idsToEmail.isEmpty() && Test.isRunningTest()) {
            AccountAccessEmailQueueable.sendEmails(idsToEmail);
            MemberAccessNotification.sendEmails(idsToEmail);
            AccountHeadRelationshipSmsQueueable.sendSms(idsToEmail);
        }
    }
}