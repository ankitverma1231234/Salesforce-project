public class VisitTiggerHandler {
    
    public static void handleAfterInsert(List<Visit> newRecords) {
        
        
        // ── Load Custom Setting ──────────────────────────────────────────────
        MessageCustomization__c setting = [
            SELECT Enable_SMS__c,
            Enable_Email__c,
            SMS_Template_Id_for_ADT__c,
            Email_Template_Id_for_ADT__c
            FROM MessageCustomization__c
            LIMIT 1
        ];
        
        System.debug('### Custom Setting loaded - Enable_SMS__c:  ' + setting.Enable_SMS__c + ' | Enable_Email__c: ' + setting.Enable_Email__c);
        System.debug('### SMS_Template_Id__c: ' + setting.SMS_Template_Id_for_ADT__c + ' | Email_Template_Id__c: ' + setting.Email_Template_Id_for_ADT__c);
        
        Boolean smsEnabled   = setting.Enable_SMS__c;
        Boolean emailEnabled = setting.Enable_Email__c;
        Id smsTemplateId     = (Id) setting.SMS_Template_Id_for_ADT__c;
        Id emailTemplateId   = (Id) setting.Email_Template_Id_for_ADT__c;
        
        if (!smsEnabled && !emailEnabled) {
            System.debug('### Both SMS and Email are disabled. Exiting early.');
            return;
        }
        
        // ── Filter qualifying Visits ─────────────────────────────────────────
        List<Visit> qualifying = new List<Visit>();
        Set<Id> accountIds = new Set<Id>();
        
        for (Visit v : newRecords) {
            
            Boolean notify = false;
            if (v.ADT_Notify__c != null) {
                notify = (Boolean) (v.ADT_Notify__c);
            }
            
            System.debug('### Visit Id: ' + v.Id + ' | ADT_Notify__c: ' + notify + ' | AccountId: ' + v.AccountId);
            
            // 👉 No Category in Visit, so only notify condition
            if (notify) {
                
                qualifying.add(v);
                
                // Visit uses AccountId
                if (v.AccountId != null) {
                    accountIds.add(v.AccountId);
                }
            }
        }
        
        System.debug('### Qualifying visits count: ' + qualifying.size());
        System.debug('### Collected AccountIds: ' + accountIds);
        
        if (qualifying.isEmpty()) {
            System.debug('### No qualifying visits found. Exiting early.');
            return;
        }
        
        // ── Fetch SMS Template ───────────────────────────────────────────────
        String smsTemplateBody = '';
        if (smsEnabled && smsTemplateId != null) {
            List<sra__Message_Template__c> templates = [
                SELECT sra__Template_Body__c
                FROM sra__Message_Template__c
                WHERE Id = :smsTemplateId
                LIMIT 1
            ];
            if (!templates.isEmpty()) {
                smsTemplateBody = templates[0].sra__Template_Body__c;
            }
            System.debug('### SMS Template fetched - Body: ' + smsTemplateBody);
        } else {
            System.debug('### SMS disabled or no SMS Template Id. Skipping SMS template fetch.');
        }
        
        // ── Fetch Person Accounts ────────────────────────────────────────────
        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id, Name, Phone, PersonEmail, PersonContactId, IsPersonAccount
            FROM Account
            WHERE Id IN :accountIds
            AND IsPersonAccount = true
        ]);
        
        System.debug('### Person Accounts fetched - Count: ' + accountMap.size());
        System.debug('### Person Account Ids: ' + accountMap.keySet());
        
        if (accountMap.isEmpty()) {
            System.debug('### No Person Accounts found. Exiting early.');
            return;
        }
        
        // ── Fetch Emergency Contacts ─────────────────────────────────────────
        List<Contact> emergencyContacts = [
            SELECT Id, Name, Phone, Email, AccountId
            FROM Contact
            WHERE AccountId IN :accountIds
            AND Emergency_Contact__c = true
        ];
        
        System.debug('### Emergency Contacts fetched - Count: ' + emergencyContacts.size());
        for (Contact con : emergencyContacts) {
            System.debug('### Emergency Contact - Id: ' + con.Id + ' | Name: ' + con.Name + ' | Phone: ' + con.Phone + ' | Email: ' + con.Email + ' | AccountId: ' + con.AccountId);
        }
        
        if (emergencyContacts.isEmpty()) {
            System.debug('### No Emergency Contacts found. Exiting early.');
            return;
        }
        
        Map<Id, List<Contact>> emergencyContactsByAccount = new Map<Id, List<Contact>>();
        for (Contact con : emergencyContacts) {
            if (!emergencyContactsByAccount.containsKey(con.AccountId)) {
                emergencyContactsByAccount.put(con.AccountId, new List<Contact>());
            }
            emergencyContactsByAccount.get(con.AccountId).add(con);
        }
        
        System.debug('### emergencyContactsByAccount map built - Keys: ' + emergencyContactsByAccount.keySet());
        
        // ── Sender Config ────────────────────────────────────────────────────
        sra__Message_User_Configuration__c senderConfig;
        if (smsEnabled) {
            List<sra__Message_User_Configuration__c> configs = [
                SELECT sra__Sender_Number__c
                FROM sra__Message_User_Configuration__c
                LIMIT 1
            ];
            if (!configs.isEmpty()) {
                senderConfig = configs[0];
                System.debug('### Sender Config loaded - Sender Number: ' + senderConfig.sra__Sender_Number__c);
            } else {
                System.debug('### No Sender Config found.');
            }
        }
        
        // ── Prepare SMS & Emails ─────────────────────────────────────────────
        List<sra__Message_History__c> smsRecords = new List<sra__Message_History__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        
        for (Visit v : qualifying) {
            
            Id accountId = v.AccountId;
            Account acc = accountMap.get(accountId);
            if (acc == null) {
                System.debug('### No matching Person Account for Visit Id: ' + v.Id + ' | AccountId: ' + accountId + '. Skipping.');
                continue;
            }
            
            List<Contact> contactsToNotify = emergencyContactsByAccount.get(accountId);
            if (contactsToNotify == null) {
                System.debug('### No Emergency Contacts mapped for AccountId: ' + accountId + '. Skipping Visit Id: ' + v.Id);
                continue;
            }
            
            System.debug('### Processing Visit Id: ' + v.Id + ' | AccountId: ' + accountId + ' | Emergency Contacts to notify: ' + contactsToNotify.size());
            
            for (Contact con : contactsToNotify) {
                
                System.debug('### Processing Contact - Id: ' + con.Id + ' | Name: ' + con.Name);
                
                // ── SMS ──────────────────────────────────────────────────────
                if (smsEnabled &&
                    senderConfig != null &&
                    String.isNotBlank(smsTemplateBody) &&
                    String.isNotBlank(con.Phone)) {
                        
                        Map<String, String> mergeMap = buildVisitMergeMap(v, con);
                        String body = FeedItemHandler.resolveMergeFields(smsTemplateBody, mergeMap);
                        
                        System.debug('### SMS prepared for Contact Id: ' + con.Id + ' | Phone: ' + con.Phone + ' | Resolved Body: ' + body);
                        
                        smsRecords.add(new sra__Message_History__c(
                            sra__Type__c              = 'Outbound',
                            sra__Sender_Number__c     = senderConfig.sra__Sender_Number__c,
                            sra__Receiver_Number__c   = con.Phone,
                            sra__Message_Body__c      = body,
                            sra__Delivery_Status__c   = 'sent',
                            sra__Related_Object_Id__c = v.Id
                        ));
                    } else {
                        System.debug('### SMS skipped for Contact Id: ' + con.Id + ' | smsEnabled: ' + smsEnabled + ' | senderConfig null: ' + (senderConfig == null) + ' | templateBody blank: ' + String.isBlank(smsTemplateBody) + ' | phone blank: ' + String.isBlank(con.Phone));
                    }
                
                // ── Email ────────────────────────────────────────────────────
                if (emailEnabled &&
                    emailTemplateId != null &&
                    String.isNotBlank(con.Email)) {
                        
                        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                        mail.setTemplateId(emailTemplateId);
                        mail.setTargetObjectId(con.Id);
                        mail.setWhatId(v.Id);
                        mail.setSaveAsActivity(false);
                        
                        System.debug('### Email prepared for Contact Id: ' + con.Id + ' | Email: ' + con.Email);
                        
                        emails.add(mail);
                    } else {
                        System.debug('### Email skipped for Contact Id: ' + con.Id + ' | emailEnabled: ' + emailEnabled + ' | templateId null: ' + (emailTemplateId == null) + ' | email blank: ' + String.isBlank(con.Email));
                    }
            }
        }
        
        System.debug('### Total SMS records to insert: ' + smsRecords.size());
        System.debug('### Total Emails to send: ' + emails.size());
        
        // ── DML ──────────────────────────────────────────────────────────────
        if (!smsRecords.isEmpty()) {
            insert smsRecords;
            System.debug('### SMS records inserted successfully. Count: ' + smsRecords.size());
        }
        
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
            System.debug('### Emails sent successfully. Count: ' + emails.size());
        }
        
        System.debug('### VisitTriggerHandler.handleAfterInsert END');
    }
    
    public static Map<String, String> buildVisitMergeMap(Visit v, Contact con) {

        System.debug('### buildVisitMergeMap called - Visit Id: ' + v?.Id + ' | Contact Id: ' + con?.Id);
        
        Map<String, String> mergeMap = new Map<String, String>();

        if (v != null) {
            for (String f : v.getPopulatedFieldsAsMap().keySet()) {
                Object val = v.get(f);
                mergeMap.put('{!' + f.toLowerCase() + '}', val != null ? String.valueOf(val) : '');
            }
        }

        if (con != null) {
            for (String f : con.getPopulatedFieldsAsMap().keySet()) {
                Object val = con.get(f);
                mergeMap.put('{!contact.' + f.toLowerCase() + '}', val != null ? String.valueOf(val) : '');
            }
        }

        System.debug('### buildVisitMergeMap - Total tokens built: ' + mergeMap.size());
        
        return mergeMap;
    }
    
}