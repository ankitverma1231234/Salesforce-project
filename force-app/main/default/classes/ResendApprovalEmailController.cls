public with sharing class ResendApprovalEmailController {
    @AuraEnabled
    public static void resendEmail(Id recordId){
        if(recordId == null){
            throw new AuraHandledException('Record ID is Required');
        }
        Account_Head_Relationship__c rec;
        try{
            rec = [SELECT Id,
                   Portal_Access_Status__c,
                   Authorized_Account_Access__r.PersonEmail,
                   Member_Account__r.PersonEmail,
                   Request_Access__c,
                   Give_Access__c
                   FROM   Account_head_relationship__c
                   WHERE  Id = :recordId
                   LIMIT  1];
        } catch (QueryException qe) {
            throw new AuraHandledException('Record not found: ' + qe.getMessage());
        }
        
        if(rec.Portal_Access_Status__c != 'Pending'){
            throw new AuraHandledException(
                'Email can only be resent when Portal Access Status is "Pending". ' +
                'Current status: ' + rec.Portal_Access_Status__c + '.'
            );
        }
        if (rec.Authorized_Account_Access__r == null ||
            String.isBlank(rec.Authorized_Account_Access__r.PersonEmail)) {
                throw new AuraHandledException(
                    'No Person Email address found on the Member Account record.'
                );
            }
        
        AccountAccessEmailQueueable.sendEmails(new Set<Id>{ recordId });
        MemberAccessNotification.sendEmails(new Set<Id>{ recordId });
    }
}