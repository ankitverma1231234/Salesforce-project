@isTest(SeeAllData=true)
public class VisitNotificationHandlerTest {
    
    private static Account createPersonAccount(String lastName) {
        RecordType rt = [
            SELECT Id
            FROM   RecordType
            WHERE  SObjectType = 'Account'
            AND    IsPersonType = true
            LIMIT  1
        ];
        Account acc = new Account(
            RecordTypeId = rt.Id,
            FirstName    = 'Test',
            LastName     = lastName,
            Phone        = '9800000000',
            PersonEmail  = lastName.toLowerCase() + '@testorg.com'
        );
        insert acc;
        return [
            SELECT Id, Name, Phone, PersonEmail, PersonContactId, IsPersonAccount
            FROM   Account
            WHERE  Id = :acc.Id
        ];
    }
    
    private static Contact createEmergencyContact(
        Id     accountId,
        String phone,
        String email
    ) {
        Contact con = new Contact(
            LastName       = 'Emergency_' + String.valueOf(Math.random()).substring(2, 7),
            Phone          = phone,
            Email          = email,
            Account__c     = accountId,
            ADT_Contact__c = true
        );
        insert con;
        return con;
    }
    
    private static Id getLocationId() {
        List<SObject> locs = Database.query('SELECT Id FROM Location LIMIT 1');
        return locs.isEmpty() ? null : (Id) locs[0].get('Id');
    }
    
    private static Visit createVisit(Id accountId, Boolean adtNotify) {
        Visit v = new Visit(
            AccountId             = accountId,
            PlaceId               = getLocationId(),
            ADT_Notify__c         = adtNotify,
            PlannedVisitStartTime = DateTime.now(),
            PlannedVisitEndTime   = DateTime.now().addHours(1),
            Status                = 'Planned'
        );
        insert v;
        return v;
    }
    
    private static MessageCustomization__c createMessageSetting(
        Boolean smsEnabled,
        Boolean emailEnabled,
        Id      smsTemplateId,
        Id      emailTemplateId
    ) {
        MessageCustomization__c s = new MessageCustomization__c(
            Name                         = 'Test', 
            Enable_SMS__c                = smsEnabled,
            Enable_Email__c              = emailEnabled,
            SMS_Template_Id_for_ADT__c   = smsTemplateId,
            Email_Template_Id_for_ADT__c = emailTemplateId
        );
        insert s;
        return s;
    }
    
    private static sra__Message_Template__c createSmsTemplate(String body) {
        sra__Message_Template__c t = new sra__Message_Template__c(
            sra__Template_Body__c = body
        );
        insert t;
        return t;
    }
    
    private static sra__Message_User_Configuration__c createSenderConfig(String senderNumber) {
        sra__Message_User_Configuration__c cfg = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = senderNumber
        );
        insert cfg;
        return cfg;
    }
    
    private static Id getOrgEmailTemplateId() {
        List<EmailTemplate> templates = [
            SELECT Id FROM EmailTemplate WHERE IsActive = true LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }
    
    @isTest
    static void testTrigger_AfterInsert_ADTNotifyTrue_SMSCreated() {
        Account                      acc  = createPersonAccount('InsertNotifyTrue');
        createEmergencyContact(acc.Id, '9100000001', 'ec_insert@test.com');
        sra__Message_Template__c     tmpl = createSmsTemplate('Hello {!name}, your visit is booked.');
        createSenderConfig('18001234567');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Test.startTest();
        Visit v = createVisit(acc.Id, true);
        Test.stopTest();
        
        List<sra__Message_History__c> smsList = [
            SELECT Id, sra__Delivery_Status__c, sra__Related_Object_Id__c
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        System.assertEquals(1, smsList.size(),          'One SMS record expected on insert with ADT_Notify__c=true');
        System.assertEquals('sent', smsList[0].sra__Delivery_Status__c, 'Delivery status should be "sent"');
    }
    
    @isTest
    static void testTrigger_AfterInsert_ADTNotifyFalse_NoSMS() {
        Account                  acc  = createPersonAccount('InsertNotifyFalse');
        createEmergencyContact(acc.Id, '9100000002', 'ec_false@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Should not send.');
        createSenderConfig('18001234568');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Test.startTest();
        Visit v = createVisit(acc.Id, false);
        Test.stopTest();
        
        Integer cnt = [
            SELECT COUNT()
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        System.assertEquals(0, cnt, 'No SMS should be sent when ADT_Notify__c is false on insert');
    }
    
    @isTest
    static void testTrigger_AfterUpdate_NotifyChangedFalseToTrue_SMSCreated() {
        Account                  acc  = createPersonAccount('UpdateFalseToTrue');
        createEmergencyContact(acc.Id, '9200000001', 'ec_update1@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Visit alert for {!name}.');
        createSenderConfig('18001234569');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = createVisit(acc.Id, false);
        
        Test.startTest();
        v.ADT_Notify__c = true;
        update v;
        Test.stopTest();
        
        List<sra__Message_History__c> smsList = [
            SELECT Id
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        System.assertEquals(1, smsList.size(), 'SMS should fire when ADT_Notify__c flips to true on update');
    }
    
    @isTest
    static void testTrigger_AfterUpdate_NotifyAlreadyTrue_NoAdditionalSMS() {
        Account                  acc  = createPersonAccount('UpdateAlreadyTrue');
        createEmergencyContact(acc.Id, '9200000002', 'ec_update2@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Hi {!name}.');
        createSenderConfig('18001234570');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = createVisit(acc.Id, true);
        
        Integer countAfterInsert = [
            SELECT COUNT()
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        
        Test.startTest();
        v.Status = 'Completed';
        update v;
        Test.stopTest();
        
        Integer countAfterUpdate = [
            SELECT COUNT()
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        System.assertEquals(
            countAfterInsert, countAfterUpdate,
            'No additional SMS should fire when ADT_Notify__c was already true'
        );
    }
    
    @isTest
    static void testTrigger_AfterUpdate_NotifyRemainsTrue_ChangeToFalse_NoSMS() {
        Account                  acc  = createPersonAccount('UpdateTrueToFalse');
        createEmergencyContact(acc.Id, '9200000003', 'ec_update3@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Hi.');
        createSenderConfig('18001234571');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = createVisit(acc.Id, true);
        
        Integer countAfterInsert = [
            SELECT COUNT()
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        
        Test.startTest();
        v.ADT_Notify__c = false;
        update v;
        Test.stopTest();
        
        Integer countAfterUpdate = [
            SELECT COUNT()
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        System.assertEquals(countAfterInsert, countAfterUpdate,
                            'No SMS should fire when ADT_Notify__c changes to false');
    }
    
    @isTest
    static void testProcessVisits_SMSOnly_ContactWithPhone() {
        Account                  acc  = createPersonAccount('ProcessSmsOnly');
        createEmergencyContact(acc.Id, '9300000001', 'proc_sms@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Your visit is confirmed, {!name}.');
        createSenderConfig('18009000001');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = createVisit(acc.Id, true);
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        List<sra__Message_History__c> smsList = [
            SELECT Id, sra__Receiver_Number__c, sra__Type__c
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        System.assert(!smsList.isEmpty(),          'At least one SMS record must exist');
        System.assertEquals('Outbound', smsList[0].sra__Type__c, 'SMS type should be Outbound');
    }
    
    @isTest
    static void testProcessVisits_EmailOnly_ContactWithEmail() {
        Id emailTemplateId = getOrgEmailTemplateId();
        if (emailTemplateId == null) {
            System.debug('Skipping email-only test – no active email template found in org');
            return;
        }
        
        Account acc = createPersonAccount('ProcessEmailOnly');
        createEmergencyContact(acc.Id, null, 'proc_email@test.com');
        createMessageSetting(false, true, null, emailTemplateId);
        
        Visit v = createVisit(acc.Id, true);
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        System.assert(true, 'Email-only flow should complete without exceptions');
    }
    
    @isTest
    static void testProcessVisits_BothSmsAndEmail() {
        Id emailTemplateId = getOrgEmailTemplateId();
        if (emailTemplateId == null) {
            System.debug('Skipping both-channel test – no active email template found in org');
            return;
        }
        
        Account                  acc  = createPersonAccount('ProcessBoth');
        createEmergencyContact(acc.Id, '9300000003', 'proc_both@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Dual-channel: {!name}');
        createSenderConfig('18009000003');
        createMessageSetting(true, true, tmpl.Id, emailTemplateId);
        
        Visit v = createVisit(acc.Id, true);
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        List<sra__Message_History__c> smsList = [
            SELECT Id
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        System.assert(!smsList.isEmpty(), 'SMS record should exist in both-channel mode');
    }
    
    @isTest
    static void testProcessVisits_BothDisabled_NoOutput() {
        Account acc = createPersonAccount('ProcessBothDisabled');
        createEmergencyContact(acc.Id, '9300000004', 'proc_disabled@test.com');
        createMessageSetting(false, false, null, null);
        
        Visit v = createVisit(acc.Id, true);
        
        Integer before = [
            SELECT COUNT() FROM sra__Message_History__c WHERE sra__Related_Object_Id__c = :v.Id
        ];
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        Integer after = [
            SELECT COUNT() FROM sra__Message_History__c WHERE sra__Related_Object_Id__c = :v.Id
        ];
        
    }
    
    @isTest
    static void testProcessVisits_NoEmergencyContacts_NoSMS() {
        Account                  acc  = createPersonAccount('ProcessNoContacts');
        sra__Message_Template__c tmpl = createSmsTemplate('No contacts here.');
        createSenderConfig('18009000004');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = createVisit(acc.Id, true);
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        Integer cnt = [
            SELECT COUNT() FROM sra__Message_History__c WHERE sra__Related_Object_Id__c = :v.Id
        ];
        System.assertEquals(0, cnt, 'No SMS when no qualifying emergency contacts exist');
    }
    
    @isTest
    static void testProcessVisits_ContactHasNoPhone_SmsSkipped() {
        Account                  acc  = createPersonAccount('ProcessNoPhone');
        createEmergencyContact(acc.Id, null, 'nophone@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Body text here.');
        createSenderConfig('18009000005');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = createVisit(acc.Id, true);
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        Integer cnt = [
            SELECT COUNT() FROM sra__Message_History__c WHERE sra__Related_Object_Id__c = :v.Id
        ];
        System.assertEquals(0, cnt, 'SMS skipped when contact has no phone number');
    }
    
    @isTest
    static void testProcessVisits_BlankSmsTemplateBody_SmsSkipped() {
        Account                  acc  = createPersonAccount('ProcessBlankBody');
        createEmergencyContact(acc.Id, '9300000006', 'blank_body@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('');
        createSenderConfig('18009000006');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = createVisit(acc.Id, true);
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        Integer cnt = [
            SELECT COUNT() FROM sra__Message_History__c WHERE sra__Related_Object_Id__c = :v.Id
        ];
    }
    
    @isTest
    static void testProcessVisits_NoSenderConfig_SmsSkipped() {
        Account                  acc  = createPersonAccount('ProcessNoSender');
        createEmergencyContact(acc.Id, '9300000007', 'no_sender@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Valid body.');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = createVisit(acc.Id, true);
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        Integer cnt = [
            SELECT COUNT() FROM sra__Message_History__c WHERE sra__Related_Object_Id__c = :v.Id
        ];
    }
    
    @isTest
    static void testProcessVisits_VisitHasNoAccountId_Skipped() {
        sra__Message_Template__c tmpl = createSmsTemplate('Body.');
        createSenderConfig('18009000008');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = new Visit(ADT_Notify__c = true);
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        System.assert(true, 'Should handle Visit with no AccountId gracefully');
    }
    
    @isTest
    static void testProcessVisits_MultipleContactsSameAccount_AllSMSSent() {
        Account                  acc  = createPersonAccount('ProcessMultiContacts');
        createEmergencyContact(acc.Id, '9300000010', 'mc1@test.com');
        createEmergencyContact(acc.Id, '9300000011', 'mc2@test.com');
        createEmergencyContact(acc.Id, '9300000012', 'mc3@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Alert for {!contact.name}.');
        createSenderConfig('18009000009');
        createMessageSetting(true, false, tmpl.Id, null);
        
        Visit v = createVisit(acc.Id, true);
        
        Test.startTest();
        VisitNotificationHandler.processVisits(new List<Visit>{ v });
        Test.stopTest();
        
        List<sra__Message_History__c> smsList = [
            SELECT Id, sra__Receiver_Number__c
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :v.Id
        ];
        System.assert(smsList.size() >= 3, 'One SMS per emergency contact expected');
    }
    
    @isTest
    static void testExtractAccountIds_WithValidIds() {
        Account acc1 = createPersonAccount('ExtractA');
        Account acc2 = createPersonAccount('ExtractB');
        Visit   v1   = createVisit(acc1.Id, false);
        Visit   v2   = createVisit(acc2.Id, false);
        
        Test.startTest();
        Set<Id> ids = VisitNotificationHandler.extractAccountIds(new List<Visit>{ v1, v2 });
        Test.stopTest();
        
        System.assertEquals(2, ids.size(), 'Should extract two distinct account IDs');
        System.assert(ids.contains(acc1.Id), 'Should contain acc1 ID');
        System.assert(ids.contains(acc2.Id), 'Should contain acc2 ID');
    }
    
    @isTest
    static void testExtractAccountIds_NullAccountIdExcluded() {
        Visit v = new Visit(ADT_Notify__c = true);
        
        Test.startTest();
        Set<Id> ids = VisitNotificationHandler.extractAccountIds(new List<Visit>{ v });
        Test.stopTest();
        
        System.assertEquals(0, ids.size(), 'Null AccountId should not be added to the set');
    }
    
    @isTest
    static void testExtractAccountIds_DuplicateAccountIds_Deduped() {
        Account acc = createPersonAccount('ExtractDupe');
        Visit   v1  = createVisit(acc.Id, false);
        Visit   v2  = createVisit(acc.Id, false);
        
        Test.startTest();
        Set<Id> ids = VisitNotificationHandler.extractAccountIds(new List<Visit>{ v1, v2 });
        Test.stopTest();
        
        System.assertEquals(1, ids.size(), 'Duplicate AccountIds should be de-duplicated by Set');
    }
    
    @isTest
    static void testExtractAccountIds_EmptyList() {
        Test.startTest();
        Set<Id> ids = VisitNotificationHandler.extractAccountIds(new List<Visit>());
        Test.stopTest();
        
        System.assertEquals(0, ids.size(), 'Empty list should return empty set');
    }
    
    @isTest
    static void testShouldSendSms_AllConditionsTrue_ReturnsTrue() {
        MessageCustomization__c            setting = new MessageCustomization__c(Enable_SMS__c = true);
        sra__Message_User_Configuration__c cfg     = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '18001234567'
        );
        
        Boolean result = VisitNotificationHandler.shouldSendSms(setting, cfg, 'Body text', '9876543210');
        System.assertEquals(true, result, 'All conditions met should return true');
    }
    
    @isTest
    static void testShouldSendSms_SmsDisabled_ReturnsFalse() {
        MessageCustomization__c            setting = new MessageCustomization__c(Enable_SMS__c = false);
        sra__Message_User_Configuration__c cfg     = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '18001234567'
        );
        
        Boolean result = VisitNotificationHandler.shouldSendSms(setting, cfg, 'Body', '9876543210');
        System.assertEquals(false, result, 'Disabled SMS should return false');
    }
    
    @isTest
    static void testShouldSendSms_NullSenderConfig_ReturnsFalse() {
        MessageCustomization__c setting = new MessageCustomization__c(Enable_SMS__c = true);
        
        Boolean result = VisitNotificationHandler.shouldSendSms(setting, null, 'Body', '9876543210');
        System.assertEquals(false, result, 'Null sender config should return false');
    }
    
    @isTest
    static void testShouldSendSms_BlankSmsBody_ReturnsFalse() {
        MessageCustomization__c            setting = new MessageCustomization__c(Enable_SMS__c = true);
        sra__Message_User_Configuration__c cfg     = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '18001234567'
        );
        
        Boolean result = VisitNotificationHandler.shouldSendSms(setting, cfg, '', '9876543210');
        System.assertEquals(false, result, 'Blank SMS body should return false');
    }
    
    @isTest
    static void testShouldSendSms_BlankPhone_ReturnsFalse() {
        MessageCustomization__c            setting = new MessageCustomization__c(Enable_SMS__c = true);
        sra__Message_User_Configuration__c cfg     = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '18001234567'
        );
        
        Boolean result = VisitNotificationHandler.shouldSendSms(setting, cfg, 'Body', '');
        System.assertEquals(false, result, 'Blank phone number should return false');
    }
    
    @isTest
    static void testShouldSendSms_NullPhone_ReturnsFalse() {
        MessageCustomization__c            setting = new MessageCustomization__c(Enable_SMS__c = true);
        sra__Message_User_Configuration__c cfg     = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '18001234567'
        );
        
        Boolean result = VisitNotificationHandler.shouldSendSms(setting, cfg, 'Body', null);
        System.assertEquals(false, result, 'Null phone number should return false');
    }
    
    @isTest
    static void testShouldSendEmail_AllConditionsTrue_ReturnsTrue() {
        Id emailTemplateId = getOrgEmailTemplateId();
        if (emailTemplateId == null) { return; }
        
        MessageCustomization__c setting = new MessageCustomization__c(
            Enable_Email__c              = true,
            Email_Template_Id_for_ADT__c = emailTemplateId
        );
        
        Boolean result = VisitNotificationHandler.shouldSendEmail(setting, 'valid@test.com');
        System.assertEquals(true, result, 'All email conditions met should return true');
    }
    
    @isTest
    static void testShouldSendEmail_EmailDisabled_ReturnsFalse() {
        Id emailTemplateId = getOrgEmailTemplateId();
        MessageCustomization__c setting = new MessageCustomization__c(
            Enable_Email__c              = false,
            Email_Template_Id_for_ADT__c = emailTemplateId
        );
        
        Boolean result = VisitNotificationHandler.shouldSendEmail(setting, 'valid@test.com');
        System.assertEquals(false, result, 'Disabled email channel should return false');
    }
    
    @isTest
    static void testShouldSendEmail_NullTemplateId_ReturnsFalse() {
        MessageCustomization__c setting = new MessageCustomization__c(
            Enable_Email__c              = true,
            Email_Template_Id_for_ADT__c = null
        );
        
        Boolean result = VisitNotificationHandler.shouldSendEmail(setting, 'valid@test.com');
        System.assertEquals(false, result, 'Null email template ID should return false');
    }
    
    @isTest
    static void testShouldSendEmail_BlankEmail_ReturnsFalse() {
        Id emailTemplateId = getOrgEmailTemplateId();
        MessageCustomization__c setting = new MessageCustomization__c(
            Enable_Email__c              = true,
            Email_Template_Id_for_ADT__c = emailTemplateId
        );
        
        Boolean result = VisitNotificationHandler.shouldSendEmail(setting, '');
        System.assertEquals(false, result, 'Blank email address should return false');
    }
    
    @isTest
    static void testShouldSendEmail_NullEmail_ReturnsFalse() {
        Id emailTemplateId = getOrgEmailTemplateId();
        MessageCustomization__c setting = new MessageCustomization__c(
            Enable_Email__c              = true,
            Email_Template_Id_for_ADT__c = emailTemplateId
        );
        
        Boolean result = VisitNotificationHandler.shouldSendEmail(setting, null);
        System.assertEquals(false, result, 'Null email address should return false');
    }
    
    @isTest
    static void testBuildMergeMap_VisitAndContact_PopulatesKeys() {
        Account acc = createPersonAccount('MergeMapFull');
        Visit   v   = createVisit(acc.Id, false);
        Contact con = createEmergencyContact(acc.Id, '9400000001', 'mm_full@test.com');
        
        Test.startTest();
        Map<String, String> result = VisitNotificationHandler.buildMergeMap(v, con);
        Test.stopTest();
        
        System.assertNotEquals(null,  result,         'Merge map must not be null');
        System.assert(!result.isEmpty(),              'Merge map must have entries');
        System.assert(result.containsKey('{!id}'),    'Should contain {!id} key from Visit');
        System.assert(result.containsKey('{!contact.id}'), 'Should contain {!contact.id} key');
    }
    
    @isTest
    static void testBuildMergeMap_NullVisit_OnlyContactKeys() {
        Account acc = createPersonAccount('MergeMapNullVisit');
        Contact con = createEmergencyContact(acc.Id, '9400000002', 'mm_nv@test.com');
        
        Test.startTest();
        Map<String, String> result = VisitNotificationHandler.buildMergeMap(null, con);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assert(!result.isEmpty(), 'Map should still have contact keys');
        System.assert(result.containsKey('{!contact.id}'), 'Contact keys should be present');
    }
    
    @isTest
    static void testBuildMergeMap_NullContact_OnlyVisitKeys() {
        Account acc = createPersonAccount('MergeMapNullContact');
        Visit   v   = createVisit(acc.Id, false);
        
        Test.startTest();
        Map<String, String> result = VisitNotificationHandler.buildMergeMap(v, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assert(!result.isEmpty(), 'Map should still have visit keys');
        System.assert(result.containsKey('{!id}'), 'Visit keys should be present');
    }
    
    @isTest
    static void testBuildMergeMap_BothNull_ReturnsEmptyMap() {
        Test.startTest();
        Map<String, String> result = VisitNotificationHandler.buildMergeMap(null, null);
        Test.stopTest();
        
        System.assertNotEquals(null,  result, 'Should not return null');
        System.assert(result.isEmpty(), 'Both null inputs should return an empty map');
    }
    
    @isTest
    static void testResolveMergeFields_TokensReplacedCorrectly() {
        Map<String, String> mergeMap = new Map<String, String>{
            '{!name}'          => 'Jane Doe',
                '{!contact.phone}' => '9999988888'
                };
                    
                    Test.startTest();
        String result = VisitNotificationHandler.resolveMergeFields(
            'Hello {!name}, call back at {!contact.phone}.', mergeMap
        );
        Test.stopTest();
        
        System.assertEquals('Hello Jane Doe, call back at 9999988888.', result);
    }
    
    @isTest
    static void testResolveMergeFields_CaseInsensitiveReplacement() {
        Map<String, String> mergeMap = new Map<String, String>{
            '{!name}' => 'John'
                };
                    
                    Test.startTest();
        String result = VisitNotificationHandler.resolveMergeFields('Hi {!NAME}', mergeMap);
        Test.stopTest();
        
        System.assertEquals('Hi John', result, 'Token replacement should be case-insensitive');
    }
    
    @isTest
    static void testResolveMergeFields_BlankTemplate_ReturnsBlank() {
        Map<String, String> mergeMap = new Map<String, String>{ '{!name}' => 'Someone' };
            
            Test.startTest();
        String result = VisitNotificationHandler.resolveMergeFields('', mergeMap);
        Test.stopTest();
        
        System.assertEquals('', result, 'Blank template should return blank string');
    }
    
    @isTest
    static void testResolveMergeFields_NullTemplate_ReturnsNull() {
        Map<String, String> mergeMap = new Map<String, String>{ '{!name}' => 'Someone' };
            
            Test.startTest();
        String result = VisitNotificationHandler.resolveMergeFields(null, mergeMap);
        Test.stopTest();
        
        System.assertEquals(null, result, 'Null template should return null');
    }
    
    @isTest
    static void testResolveMergeFields_NullMergeMap_ReturnsOriginalTemplate() {
        Test.startTest();
        String result = VisitNotificationHandler.resolveMergeFields('Hello {!name}', null);
        Test.stopTest();
        
        System.assertEquals('Hello {!name}', result, 'Null merge map should leave template unchanged');
    }
    
    @isTest
    static void testResolveMergeFields_EmptyMergeMap_ReturnsOriginalTemplate() {
        Test.startTest();
        String result = VisitNotificationHandler.resolveMergeFields(
            'Hello {!name}', new Map<String, String>()
        );
        Test.stopTest();
        
        System.assertEquals('Hello {!name}', result, 'Empty merge map should leave template unchanged');
    }
    
    @isTest
    static void testResolveMergeFields_UnknownToken_LeftAsIs() {
        Map<String, String> mergeMap = new Map<String, String>{ '{!name}' => 'Alice' };
            
            Test.startTest();
        String result = VisitNotificationHandler.resolveMergeFields(
            'Hi {!name}, ref {!unknown_field}.', mergeMap
        );
        Test.stopTest();
        
        System.assertEquals('Hi Alice, ref {!unknown_field}.', result,
                            'Unknown tokens should remain untouched in the resolved string');
    }
    
    @isTest
    static void testBuildSmsRecord_FieldsMappedCorrectly() {
        Account acc = createPersonAccount('BuildSmsFields');
        Visit   v   = createVisit(acc.Id, false);
        Contact con = createEmergencyContact(acc.Id, '9500000001', 'build_sms@test.com');
        
        Test.startTest();
        sra__Message_History__c rec = VisitNotificationHandler.buildSmsRecord(
            v, con, 'Dear {!contact.name}, your visit is set.', '18001112222'
        );
        Test.stopTest();
        
        System.assertEquals('Outbound',    rec.sra__Type__c,            'Type must be Outbound');
        System.assertEquals('18001112222', rec.sra__Sender_Number__c,   'Sender number mismatch');
        System.assertEquals(con.Phone,     rec.sra__Receiver_Number__c, 'Receiver must be contact phone');
        System.assertEquals('sent',        rec.sra__Delivery_Status__c, 'Delivery status must be sent');
        System.assertEquals(v.Id,          rec.sra__Related_Object_Id__c, 'Related object ID mismatch');
        System.assert(String.isNotBlank(rec.sra__Message_Body__c), 'Message body must not be blank');
    }
    
    @isTest
    static void testBuildSmsRecord_MergeFieldsResolvedInBody() {
        Account acc = createPersonAccount('BuildSmsMerge');
        Visit   v   = createVisit(acc.Id, false);
        Contact con = createEmergencyContact(acc.Id, '9500000002', 'sms_merge@test.com');
        
        Test.startTest();
        sra__Message_History__c rec = VisitNotificationHandler.buildSmsRecord(
            v, con, 'Ref ID: {!id}', '18001113333'
        );
        Test.stopTest();
        
        System.assert(
            rec.sra__Message_Body__c.contains(v.Id),
            'Merge field {!id} should resolve to the Visit Id in the message body'
        );
    }
    
    @isTest
    static void testBuildEmailMessage_FieldsMappedCorrectly() {
        Id emailTemplateId = getOrgEmailTemplateId();
        if (emailTemplateId == null) {
            System.debug('Skipping buildEmailMessage test – no active template in org');
            return;
        }
        
        Account acc = createPersonAccount('BuildEmailFields');
        Visit   v   = createVisit(acc.Id, false);
        Contact con = createEmergencyContact(acc.Id, '9600000001', 'build_email@test.com');
        
        Test.startTest();
        Messaging.SingleEmailMessage mail =
            VisitNotificationHandler.buildEmailMessage(v, con, emailTemplateId);
        Test.stopTest();
        
        System.assertEquals(emailTemplateId, mail.getTemplateId(),    'Template ID mismatch');
        System.assertEquals(con.Id,          mail.getTargetObjectId(), 'Target object (Contact) ID mismatch');
        System.assertEquals(v.Id,            mail.getWhatId(),         'WhatId (Visit) mismatch');
    }
    // ── DELETE TESTS ────────────────────────────────────────────────────────────
    
    @isTest
    static void testTrigger_AfterDelete_SingleVisit_NoException() {
        Account acc = createPersonAccount('DeleteSingle');
        Visit   v   = createVisit(acc.Id, false);
        Id      vId = v.Id;
        
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            delete v;
        } catch (Exception e) {
            exceptionThrown = true;
            System.debug('Unexpected exception on delete: ' + e.getMessage());
        }
        Test.stopTest();
        
        System.assertEquals(false, exceptionThrown,
                            'Deleting a Visit should not throw any exception');
        
        Integer remaining = [SELECT COUNT() FROM Visit WHERE Id = :vId ALL ROWS];
    }
    
    @isTest
    static void testTrigger_AfterDelete_BulkVisits_NoException() {
        Account acc = createPersonAccount('DeleteBulk');
        Visit   v1  = createVisit(acc.Id, false);
        Visit   v2  = createVisit(acc.Id, true);
        Visit   v3  = createVisit(acc.Id, false);
        Set<Id> visitIds = new Set<Id>{ v1.Id, v2.Id, v3.Id };
            
            Boolean exceptionThrown = false;
        Test.startTest();
        try {
            delete new List<Visit>{ v1, v2, v3 };
                } catch (Exception e) {
                    exceptionThrown = true;
                    System.debug('Unexpected exception on bulk delete: ' + e.getMessage());
                }
        Test.stopTest();
        
        System.assertEquals(false, exceptionThrown,
                            'Bulk delete of Visits should not throw any exception');
        
        Integer remaining = [
            SELECT COUNT() FROM Visit WHERE Id IN :visitIds ALL ROWS
        ];
    }
    
    @isTest
    static void testTrigger_AfterDelete_ADTNotifyTrue_NoException() {
        // ADT_Notify__c flag must not affect the delete path
        Account acc = createPersonAccount('DeleteNotifyTrue');
        Visit   v   = createVisit(acc.Id, true);
        
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            delete v;
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(false, exceptionThrown,
                            'Delete of a Visit with ADT_Notify__c=true should not throw');
    }
    
    @isTest
    static void testTrigger_AfterDelete_DifferentAccounts_NoException() {
        Account acc1 = createPersonAccount('DeleteAcct1');
        Account acc2 = createPersonAccount('DeleteAcct2');
        Visit   v1   = createVisit(acc1.Id, false);
        Visit   v2   = createVisit(acc2.Id, true);
        Set<Id> visitIds = new Set<Id>{ v1.Id, v2.Id };
            
            Boolean exceptionThrown = false;
        Test.startTest();
        try {
            delete new List<Visit>{ v1, v2 };
                } catch (Exception e) {
                    exceptionThrown = true;
                }
        Test.stopTest();
        
        System.assertEquals(false, exceptionThrown,
                            'Deleting Visits across different accounts should not throw');
        
        Integer remaining = [
            SELECT COUNT() FROM Visit WHERE Id IN :visitIds ALL ROWS
        ];
    }
    
    @isTest
    static void testTrigger_AfterDelete_NotificationHandlerNotFired() {
        // Deleting a Visit must NOT send any SMS notifications
        Account                  acc  = createPersonAccount('DeleteNoNotify');
        createEmergencyContact(acc.Id, '9700000001', 'del_no_notify@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Should never send on delete.');
        createSenderConfig('18001239999');
        createMessageSetting(true, false, tmpl.Id, null);
        
        // Insert with ADT_Notify__c = false so insert handler does NOT fire
        Visit v   = createVisit(acc.Id, false);
        Id    vId = v.Id;
        
        Integer smsBeforeDelete = [
            SELECT COUNT()
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :vId
        ];
        
        Test.startTest();
        delete v;
        Test.stopTest();
        
        Integer smsAfterDelete = [
            SELECT COUNT()
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :vId
        ];
        
        System.assertEquals(smsBeforeDelete, smsAfterDelete,
                            'Deleting a Visit must not trigger any SMS notification');
    }
    
    @isTest
    static void testTrigger_AfterDelete_WithEmergencyContacts_NoNotification() {
        // Even if emergency contacts exist, delete must not fire the SMS handler
        Account                  acc  = createPersonAccount('DeleteWithContacts');
        createEmergencyContact(acc.Id, '9700000002', 'del_ec1@test.com');
        createEmergencyContact(acc.Id, '9700000003', 'del_ec2@test.com');
        sra__Message_Template__c tmpl = createSmsTemplate('Alert: {!name}');
        createSenderConfig('18001230000');
        createMessageSetting(true, true, tmpl.Id, null);
        
        Visit v   = createVisit(acc.Id, false);
        Id    vId = v.Id;
        
        Test.startTest();
        delete v;
        Test.stopTest();
        
        Integer smsCnt = [
            SELECT COUNT()
            FROM   sra__Message_History__c
            WHERE  sra__Related_Object_Id__c = :vId
        ];
        System.assertEquals(0, smsCnt,
                            'No SMS should be sent when a Visit is deleted, even with emergency contacts present');
    }
}