public without sharing class MemberAccessNotification {
    @future(callout=false)
    public static void sendEmails(Set<Id> relationshipIds){
        if (relationshipIds == null || relationshipIds.isEmpty()) return;
        
        EmailTemplate tmpl;
        try{
            tmpl = [
                SELECT Id, Subject, HtmlValue, Body
                FROM   EmailTemplate
                WHERE  DeveloperName = :Label.Member_Approval_Template 
                LIMIT  1];
        } Catch(QueryException qe){
            System.debug(LoggingLevel.ERROR, 'Member Template Not found' + qe.getMessage());
            return;
        }
        List<OrgWideEmailAddress> owea = [Select Id from OrgWideEmailAddress LIMIT 1];
        Map<Id, Account_head_relationship__c> records = new Map<Id, Account_head_relationship__c>([
            SELECT Id,
            Member_Account__c,
            Member_Account__r.PersonEmail,
            Authorized_Account_Access__r.PersonEmail,
            Member_Account__r.Name,
            Authorized_Account_Access__c,
            Authorized_Account_Access__r.Name,
            Authorized_Account_Access__r.FirstName,
            Verification_Code__c,
            Approval_Token__c,
            Give_Access__c,
            Token_Expiry__c
            FROM   Account_head_relationship__c
            WHERE  Id IN :relationshipIds
        ]);
        
        List<Messaging.SingleEmailMessage> outbound = new List<Messaging.SingleEmailMessage>();
        for (Account_head_relationship__c r : records.values()){

            if (r.Give_Access__c != true) {
                System.debug(LoggingLevel.INFO,
                             'Skipping email – Request_Access__c is false for record: ' + r.Id);
                continue;
            }
           
            String toAddress = (r.Authorized_Account_Access__r != null)
                    ? r.Authorized_Account_Access__r.PersonEmail
                    : null;
            
            if(String.isBlank(toAddress)){
                System.debug(LoggingLevel.WARN,
                             'Skipping – no PersonEmail on Member_Account__r for record: ' + r.Id);
                continue;
            }
            Messaging.SingleEmailMessage msg;
            try{
                msg = Messaging.renderStoredEmailTemplate(tmpl.Id, null, r.Id);
            } Catch (Exception ex){
                System.debug(LoggingLevel.ERROR,
                             'Member template render failed for ' + r.Id + ': ' + ex.getMessage());
                continue;
            }
            msg.setToAddresses(new List<String>{ toAddress });
            msg.setSaveAsActivity(false);
            if (!owea.isEmpty()) {
                msg.setOrgWideEmailAddressId(owea[0].Id);
            }
            outbound.add(msg);    
        } 
        if(!outbound.isEmpty()){
            Messaging.SendEmailResult[] results = Messaging.sendEmail(outbound, false);
            for (Messaging.SendEmailResult res : results) {
                if (!res.isSuccess()) {
                    for (Messaging.SendEmailError err : res.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                                     'Member email send failed: ' + err.getStatusCode() + ' – ' + err.getMessage());
                    }
                }
            }
        }
    }
}