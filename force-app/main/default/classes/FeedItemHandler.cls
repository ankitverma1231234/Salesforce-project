public class FeedItemHandler {
    
    private static Id getExcludedUserId() {
        List<User> users = [
            SELECT Id 
            FROM User 
            WHERE Name = 'Member Portal Site Guest User' 
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].Id;
    }
    public static void handleAfterInsert(List<FeedItem> newItems) {
        Id excludedUserId = getExcludedUserId();
        Set<Id> caseIds = new Set<Id>();
        for (FeedItem fi : newItems) {
            if (fi.ParentId != null &&
                String.valueOf(fi.ParentId).startsWith('500') &&
                (excludedUserId == null || fi.CreatedById != excludedUserId)) {
                    caseIds.add(fi.ParentId);
                }
        }
        if (caseIds.isEmpty()) return;
        MessageCustomization__c setting = [
            SELECT Chatter_Sms_Notification__c,
            Chatter_Email_Notification__c,
            Chatter_Sms_Notification_Message__c,
            Email_Template_ID__c
            FROM MessageCustomization__c
            LIMIT 1
        ];
        Boolean smsEnabled   = setting.Chatter_Sms_Notification__c;
        Boolean emailEnabled = setting.Chatter_Email_Notification__c;
        Id emailTemplateId   = (Id)setting.Email_Template_ID__c;
        Id smsTemplateId     = (Id) setting.Chatter_Sms_Notification_Message__c;
        if (!smsEnabled && !emailEnabled) return;
        String smsTemplateBody = '';
        if (smsEnabled && smsTemplateId != null) {
            List<sra__Message_Template__c> templates = [
                SELECT Id, Name, sra__Object_Name__c,
                sra__Template_Body__c, sra__Estimated_Segments__c
                FROM sra__Message_Template__c
                WHERE Id = :smsTemplateId
                LIMIT 1
            ];
            if (!templates.isEmpty()) {
                smsTemplateBody = templates[0].sra__Template_Body__c;
            }
        }
        Map<Id, Case> caseMap = new Map<Id, Case>([
            SELECT Id, CaseNumber, Subject, Status,
            AccountId,
            Account.IsPersonAccount,
            Account.PersonEmail,
            Account.Name,
            Account.AccountNumber,
            Account.PersonContactId,
            Account.Phone
            FROM Case
            WHERE Id IN :caseIds
        ]);
        
        if (caseMap.isEmpty()) return;
        Set<Id> accountIds = new Set<Id>();
        for (Case c : caseMap.values()) {
            if (c.AccountId != null) {
                accountIds.add(c.AccountId);
            }
        }
        Map<Id, Account> accountMap = new Map<Id, Account>();
        if (!accountIds.isEmpty()) {
            accountMap = new Map<Id, Account>([
                SELECT Id, Name, AccountNumber, Phone,
                PersonEmail, PersonContactId, IsPersonAccount
                FROM Account
                WHERE Id IN :accountIds
            ]);
        }
        sra__Message_User_Configuration__c senderConfig;
        
        if (smsEnabled) {
            List<sra__Message_User_Configuration__c> configs = [
                SELECT sra__Sender_Number__c
                FROM sra__Message_User_Configuration__c
                LIMIT 1
            ];
            if (!configs.isEmpty()) {
                senderConfig = configs[0];
            }
        }
        List<sra__Message_History__c> smsRecords = new List<sra__Message_History__c>();
        List<Messaging.SingleEmailMessage> emails  = new List<Messaging.SingleEmailMessage>();
        for (FeedItem fi : newItems) {
            if (fi.ParentId == null ||
                !String.valueOf(fi.ParentId).startsWith('500') ||
                (excludedUserId != null && fi.CreatedById == excludedUserId)) {
                    continue;
                }
            Case c = caseMap.get(fi.ParentId);
            if (c == null) continue;
            Account acc = accountMap.get(c.AccountId);
            if (acc == null || !acc.IsPersonAccount) continue;
            if (smsEnabled && senderConfig != null && String.isNotBlank(smsTemplateBody)) {
                String phone = acc.Phone;
                if (String.isNotBlank(phone)) {
                    Map<String, String> mergeMap = buildMergeMap(c, acc);
                    String body = resolveMergeFields(smsTemplateBody, mergeMap);
                    smsRecords.add(new sra__Message_History__c(
                        sra__Type__c              = 'Outbound',
                        sra__Sender_Number__c     = senderConfig.sra__Sender_Number__c,
                        sra__Receiver_Number__c   = phone,
                        sra__Message_Body__c      = body,
                        sra__Delivery_Status__c   = 'sent',
                        sra__Related_Object_Id__c = c.Id
                    ));
                }
            }
            if (emailEnabled &&
                String.isNotBlank(emailTemplateId) &&
                String.isNotBlank(acc.PersonEmail)) {
                    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                    mail.setTemplateId(emailTemplateId);
                    mail.setWhatId(c.AccountId);
                    mail.setTargetObjectId(acc.PersonContactId);
                    mail.setSaveAsActivity(false);
                    mail.setOrgWideEmailAddressId('0D2Kc000000Kym3KAC');
                    emails.add(mail);
                }
        }
        if (!smsRecords.isEmpty()) {
            insert smsRecords;
        }
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }
    public static Map<String, String> buildMergeMap(Case c, Account acc) {
        Map<String, String> mergeMap = new Map<String, String>();
        if (c != null) {
            Map<String, Object> caseFields = ((SObject) c).getPopulatedFieldsAsMap();
            for (String fieldName : caseFields.keySet()) {
                Object fieldValue = caseFields.get(fieldName);
                String token      = '{!' + fieldName.toLowerCase() + '}';
                String value      = fieldValue != null ? String.valueOf(fieldValue) : '';
                mergeMap.put(token, value);
            }
        }
        if (acc != null) {
            Map<String, Object> accountFields = ((SObject) acc).getPopulatedFieldsAsMap();
            for (String fieldName : accountFields.keySet()) {
                Object fieldValue = accountFields.get(fieldName);
                String token      = '{!account.' + fieldName.toLowerCase() + '}';
                String value      = fieldValue != null ? String.valueOf(fieldValue) : '';
                mergeMap.put(token, value);
            }
        }
        return mergeMap;
    }
    public static String resolveMergeFields(String templateBody, Map<String, String> mergeMap) {
        if (String.isBlank(templateBody) || mergeMap == null || mergeMap.isEmpty()) {
            return templateBody;
        }
        String resolved = templateBody;
        for (String token : mergeMap.keySet()) {
            resolved = resolved.replaceAll(
                '(?i)' + Pattern.quote(token),
                Matcher.quoteReplacement(mergeMap.get(token)));
        }
        return resolved;
    }
    
}