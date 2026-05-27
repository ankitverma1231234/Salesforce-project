public class CareObservationHandler {
    
public static void handleAfterInsert(List<CareObservation> newRecords) {
        
    MessageCustomization__c setting = fetchMessageSetting();
    if (setting == null)                          return;
    if (!setting.Enable_SMS__c && !setting.Enable_Email__c) return;
    
    List<CareObservation> qualifying = filterQualifying(newRecords);
    if (qualifying.isEmpty())                     return;
    
    Set<Id> accountIds = extractAccountIds(qualifying);
    
    
    String smsBody = (setting.Enable_SMS__c && setting.SMS_Template_Id_for_ADT__c != null)
        ? fetchSmsTemplateBody(setting.SMS_Template_Id_for_ADT__c)
        : '';
    
    Map<Id, Account>        accountMap       = fetchPersonAccounts(accountIds);
    if (accountMap.isEmpty()) return;
    
    Map<Id, List<Contact>>  contactsByAcct   = fetchEmergencyContacts(accountIds);
    if (contactsByAcct.isEmpty()) return;
    
    sra__Message_User_Configuration__c senderCfg = setting.Enable_SMS__c
        ? fetchSenderConfig()
        : null;
    
    List<sra__Message_History__c>      smsRecords = new List<sra__Message_History__c>();
    List<Messaging.SingleEmailMessage> emails     = new List<Messaging.SingleEmailMessage>();
    
    for (CareObservation obs : qualifying) {
        Account      acc      = accountMap.get(obs.ObservedSubjectId);
        List<Contact> contacts = contactsByAcct.get(obs.ObservedSubjectId);
        if (acc == null || contacts == null) continue;
        
        for (Contact con : contacts) {
            if (shouldSendSms(setting, senderCfg, smsBody, con.Phone)) {
                smsRecords.add(buildSmsRecord(obs, con, smsBody, senderCfg.sra__Sender_Number__c));
            }
            if (shouldSendEmail(setting, con.Email)) {
                emails.add(buildEmailMessage(obs, con, setting.Email_Template_Id_for_ADT__c));
            }
        }
    }
    
    if (!smsRecords.isEmpty()) insert smsRecords;
    if (!emails.isEmpty())     Messaging.sendEmail(emails, false);
}
    
    // ── Filter Logic ──────────────────────────────────────────────────────────
    @TestVisible
    private static List<CareObservation> filterQualifying(List<CareObservation> records) {
        Boolean hasAdtField = Schema.SObjectType.CareObservation.fields
            .getMap().containsKey('adt_notify__c');
        
        List<CareObservation> result = new List<CareObservation>();
        for (CareObservation obs : records) {
            Boolean notify = hasAdtField
                ? (obs.get('ADT_Notify__c') != null ? (Boolean) obs.get('ADT_Notify__c') : false)
                : true;  
            
            if (obs.Category == 'Vital-Signs' && notify) {
                result.add(obs);
            }
        }
        return result;
    }
    
    @TestVisible
    private static Set<Id> extractAccountIds(List<CareObservation> records) {
        Set<Id> ids = new Set<Id>();
        for (CareObservation obs : records) {
            if (obs.ObservedSubjectId != null) ids.add(obs.ObservedSubjectId);
        }
        return ids;
    }
    
    
    @TestVisible
    private static Boolean shouldSendSms(
        MessageCustomization__c setting,
        sra__Message_User_Configuration__c senderCfg,
        String smsBody,
        String phone
    ) {
        return setting.Enable_SMS__c
            && senderCfg != null
            && String.isNotBlank(smsBody)
            && String.isNotBlank(phone);
    }
    
    @TestVisible
    private static Boolean shouldSendEmail(MessageCustomization__c setting, String email) {
        return setting.Enable_Email__c
            && setting.Email_Template_Id_for_ADT__c != null
            && String.isNotBlank(email);
    }
    
    @TestVisible
    private static sra__Message_History__c buildSmsRecord(
        CareObservation obs,
        Contact         con,
        String          templateBody,
        String          senderNumber
    ) {
        String resolvedBody = resolveMergeFields(templateBody, buildMergeMap(obs, con));
        
        sra__Message_History__c rec = new sra__Message_History__c(
            sra__Type__c              = 'Outbound',
            sra__Sender_Number__c     = senderNumber,
            sra__Receiver_Number__c   = con.Phone,
            sra__Message_Body__c      = resolvedBody,
            sra__Delivery_Status__c   = 'sent',
            sra__Related_Object_Id__c = obs.Id
        );
        
        System.debug('SMS_DEBUG >> Built SMS Record: ' + rec);
        
        return rec;
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildEmailMessage(
        CareObservation obs,
        Contact         con,
        Id              templateId
    ) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTemplateId(templateId);
        mail.setTargetObjectId(con.Id);
        mail.setWhatId(obs.Id);
        mail.setSaveAsActivity(false);
        return mail;
    }
    
    @TestVisible
    public static Map<String, String> buildMergeMap(CareObservation obs, Contact con) {
        Map<String, String> mergeMap = new Map<String, String>();
        
        if (obs != null) {
            for (String field : ((SObject) obs).getPopulatedFieldsAsMap().keySet()) {
                Object val = ((SObject) obs).getPopulatedFieldsAsMap().get(field);
                mergeMap.put('{!' + field.toLowerCase() + '}',
                             val != null ? String.valueOf(val) : '');
            }
        }
        if (con != null) {
            for (String field : ((SObject) con).getPopulatedFieldsAsMap().keySet()) {
                Object val = ((SObject) con).getPopulatedFieldsAsMap().get(field);
                mergeMap.put('{!contact.' + field.toLowerCase() + '}',
                             val != null ? String.valueOf(val) : '');
            }
        }
        return mergeMap;
    }
    
    @TestVisible
    public static String resolveMergeFields(String templateBody, Map<String, String> mergeMap) {
        if (String.isBlank(templateBody) || mergeMap == null || mergeMap.isEmpty()) {
            return templateBody;
        }
        String resolved = templateBody;
        for (String token : mergeMap.keySet()) {
            resolved = resolved.replaceAll(
                '(?i)' + Pattern.quote(token),
                Matcher.quoteReplacement(mergeMap.get(token))
            );
        }
        return resolved;
    }
    
  
    @TestVisible
    private static MessageCustomization__c fetchMessageSetting() {
        List<MessageCustomization__c> rows = [
            SELECT Enable_SMS__c, Enable_Email__c,
            SMS_Template_Id_for_ADT__c, Email_Template_Id_for_ADT__c
            FROM   MessageCustomization__c
            LIMIT  1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
    
    @TestVisible
    private static String fetchSmsTemplateBody(Id templateId) {
        List<sra__Message_Template__c> rows = [
            SELECT sra__Template_Body__c
            FROM   sra__Message_Template__c
            WHERE  Id = :templateId
            LIMIT  1
        ];
        return rows.isEmpty() ? '' : rows[0].sra__Template_Body__c;
    }
    
    @TestVisible
    private static Map<Id, Account> fetchPersonAccounts(Set<Id> accountIds) {
        return new Map<Id, Account>([
            SELECT Id, Name, Phone, PersonEmail, PersonContactId, IsPersonAccount
            FROM   Account
            WHERE  Id IN :accountIds
            AND    IsPersonAccount = true
        ]);
    }
    
    @TestVisible
    private static Map<Id, List<Contact>> fetchEmergencyContacts(Set<Id> accountIds) {
        List<Contact> rows = [
            SELECT Id, Name, Phone, Email, AccountId, Account__c
            FROM   Contact
            WHERE  Account__c    IN :accountIds
            AND    ADT_Contact__c = true
        ];
        
        Map<Id, List<Contact>> byAccount = new Map<Id, List<Contact>>();
        for (Contact con : rows) {
            if (!byAccount.containsKey(con.Account__c)) {
                byAccount.put(con.Account__c, new List<Contact>());
            }
            byAccount.get(con.Account__c).add(con);
        }
        return byAccount;
    }
    
    @TestVisible
    private static sra__Message_User_Configuration__c fetchSenderConfig() {
        List<sra__Message_User_Configuration__c> rows = [
            SELECT sra__Sender_Number__c
            FROM   sra__Message_User_Configuration__c
            LIMIT  1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}