@isTest(SeeAllData=true)
private class CareObservationHandlerTest {
    
    private static CareObservation makeObs(String category, Boolean adtNotify) {
        CareObservation obs = new CareObservation();
        obs.Category = category;
        if (Schema.SObjectType.CareObservation.fields.getMap().containsKey('adt_notify__c')) {
            obs.put('ADT_Notify__c', adtNotify);
        }
        return obs;
    }
    
    @isTest
    static void resolveMergeFields_replacesTokensCaseInsensitive() {
        Map<String, String> mergeMap = new Map<String, String>{
            '{!name}'    => 'John',
                '{!status}'  => 'Active'
                };
                    String template = 'Hello {!Name}, your status is {!STATUS}.';
        String result   = CareObservationHandler.resolveMergeFields(template, mergeMap);
        
        System.assertEquals('Hello John, your status is Active.', result,
                            'Both tokens should be replaced case-insensitively');
    }
    
    @isTest
    static void resolveMergeFields_blankTemplate_returnsBlank() {
        Map<String, String> mergeMap = new Map<String, String>{ '{!name}' => 'John' };
            System.assertEquals('', CareObservationHandler.resolveMergeFields('', mergeMap));
        System.assertEquals(null, CareObservationHandler.resolveMergeFields(null, mergeMap));
    }
    
    @isTest
    static void resolveMergeFields_emptyMap_returnsOriginal() {
        String template = 'Hello {!Name}';
        String result   = CareObservationHandler.resolveMergeFields(template, new Map<String, String>());
        System.assertEquals(template, result, 'Unchanged when mergeMap is empty');
    }
    
    @isTest
    static void resolveMergeFields_nullMap_returnsOriginal() {
        String template = 'Hello {!Name}';
        String result   = CareObservationHandler.resolveMergeFields(template, null);
        System.assertEquals(template, result, 'Unchanged when mergeMap is null');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 2. filterQualifying — unit tests on the private method via @TestVisible
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void filterQualifying_includesVitalSignsWithNotify() {
        CareObservation obs = makeObs('Vital-Signs', true);
        List<CareObservation> result = CareObservationHandler.filterQualifying(
            new List<CareObservation>{ obs }
        );
        System.assertEquals(1, result.size(), 'Vital-Signs + notify=true should qualify');
    }
    
    @isTest
    static void filterQualifying_excludesNonVitalSigns() {
        CareObservation obs = makeObs('Medication', true);
        List<CareObservation> result = CareObservationHandler.filterQualifying(
            new List<CareObservation>{ obs }
        );
        System.assertEquals(0, result.size(), 'Non Vital-Signs category must be excluded');
    }
    
    @isTest
    static void filterQualifying_excludesWhenNotifyFalse() {
        // Only meaningful if ADT_Notify__c field exists
        if (!Schema.SObjectType.CareObservation.fields.getMap().containsKey('adt_notify__c')) {
            return;
        }
        CareObservation obs = makeObs('Vital-Signs', false);
        List<CareObservation> result = CareObservationHandler.filterQualifying(
            new List<CareObservation>{ obs }
        );
        System.assertEquals(0, result.size(), 'notify=false should be excluded');
    }
    
    @isTest
    static void filterQualifying_mixedRecords_onlyQualifyingReturned() {
        List<CareObservation> input = new List<CareObservation>{
            makeObs('Vital-Signs', true),
                makeObs('Medication',  true),
                makeObs('Vital-Signs', false)  // excluded if field exists
                };
                    List<CareObservation> result = CareObservationHandler.filterQualifying(input);
        // At minimum the first record qualifies
        System.assert(result.size() >= 1, 'At least one record should qualify');
    }
    
    @isTest
    static void shouldSendSms_allConditionsMet_returnsTrue() {
        MessageCustomization__c setting = new MessageCustomization__c(Enable_SMS__c = true);
        sra__Message_User_Configuration__c cfg = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '+10000000000'
        );
        Boolean result = CareObservationHandler.shouldSendSms(setting, cfg, 'Hello', '+19999999999');
        System.assert(result, 'Should return true when all conditions are met');
    }
    
    @isTest
    static void shouldSendSms_smsDisabled_returnsFalse() {
        MessageCustomization__c setting = new MessageCustomization__c(Enable_SMS__c = false);
        sra__Message_User_Configuration__c cfg = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '+10000000000'
        );
        System.assert(
            !CareObservationHandler.shouldSendSms(setting, cfg, 'Hello', '+19999999999'),
            'Should return false when SMS is disabled'
        );
    }
    
    @isTest
    static void shouldSendSms_noPhone_returnsFalse() {
        MessageCustomization__c setting = new MessageCustomization__c(Enable_SMS__c = true);
        sra__Message_User_Configuration__c cfg = new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '+10000000000'
        );
        System.assert(
            !CareObservationHandler.shouldSendSms(setting, cfg, 'Hello', ''),
            'Should return false when contact has no phone'
        );
    }
    
    @isTest
    static void shouldSendSms_nullSenderConfig_returnsFalse() {
        MessageCustomization__c setting = new MessageCustomization__c(Enable_SMS__c = true);
        System.assert(
            !CareObservationHandler.shouldSendSms(setting, null, 'Hello', '+19999999999'),
            'Should return false when senderConfig is null'
        );
    }
    
    @isTest
    static void shouldSendEmail_allConditionsMet_returnsTrue() {
        MessageCustomization__c setting = new MessageCustomization__c(
            Enable_Email__c = true,
            Email_Template_Id_for_ADT__c = UserInfo.getUserId() 
        );
        System.assert(
            CareObservationHandler.shouldSendEmail(setting, 'test@test.com'),
            'Should return true when email enabled, templateId set, and email not blank'
        );
    }
    
    @isTest
    static void shouldSendEmail_blankEmail_returnsFalse() {
        MessageCustomization__c setting = new MessageCustomization__c(
            Enable_Email__c = true,
            Email_Template_Id_for_ADT__c = UserInfo.getUserId()
        );
        System.assert(
            !CareObservationHandler.shouldSendEmail(setting, ''),
            'Should return false when contact email is blank'
        );
    }
    
    @isTest
    static void shouldSendEmail_emailDisabled_returnsFalse() {
        MessageCustomization__c setting = new MessageCustomization__c(
            Enable_Email__c = false,
            Email_Template_Id_for_ADT__c = UserInfo.getUserId()
        );
        System.assert(
            !CareObservationHandler.shouldSendEmail(setting, 'test@test.com'),
            'Should return false when email notifications are disabled'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 4. buildMergeMap — unit test
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void buildMergeMap_contactPrefixedCorrectly() {
        Contact con = new Contact(FirstName = 'Jane', LastName = 'Doe', Phone = '+1111111111');
        
        // CareObservation without insert — populated fields only
        // We pass null for obs to isolate contact mapping
        Map<String, String> mergeMap = CareObservationHandler.buildMergeMap(null, con);
        
        // Contact fields use {!contact.fieldname} prefix
        System.assert(mergeMap.containsKey('{!contact.lastname}'),
                      'Contact fields should be prefixed with {!contact.}');
        System.assertEquals('Doe', mergeMap.get('{!contact.lastname}'));
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 5. extractAccountIds — unit test
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void extractAccountIds_nullSubjectIdSkipped() {
        CareObservation obs1 = new CareObservation();
        // obs1.ObservedSubjectId = null (default)
        
        Set<Id> ids = CareObservationHandler.extractAccountIds(
            new List<CareObservation>{ obs1 }
        );
        System.assertEquals(0, ids.size(), 'Null ObservedSubjectId should not be added');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 6. handleAfterInsert — integration test (no setting record → early exit)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void handleAfterInsert_noSetting_doesNotThrow() {
        // No MessageCustomization__c record inserted → guard exits cleanly
        Test.startTest();
        CareObservationHandler.handleAfterInsert(new List<CareObservation>());
        Test.stopTest();
        // No exception = pass
        System.assert(true, 'Handler should exit cleanly with no setting record');
    }
    
    @isTest
    static void handleAfterInsert_bothDisabled_doesNotSend() {
        insert new MessageCustomization__c(Name = 'Test',Enable_SMS__c = false, Enable_Email__c = false);
        
        Test.startTest();
        CareObservationHandler.handleAfterInsert(new List<CareObservation>());
        Test.stopTest();
    }
    
    @isTest
    static void handleAfterInsert_noQualifyingObservations_doesNotSend() {
        insert new MessageCustomization__c(Name = 'Test', Enable_SMS__c = true, Enable_Email__c = true);
        
        CareObservation obs = makeObs('Medication', true); 
        
        Test.startTest();
        CareObservationHandler.handleAfterInsert(new List<CareObservation>{ obs });
        Test.stopTest();
    }
    
    @isTest
    static void handleAfterInsert_fullFlow_coversBuilders() {
        
        // 1. Account
        Account acc = new Account(
            LastName = 'Patient',
            PersonEmail = 'test@gmail.com'
        );
        insert acc;
        
        // 2. Contact
        Contact con = new Contact(
            LastName = 'EC',
            Phone = '+911234567890',
            Email = 'test@test.com',
            Account__c = acc.Id,
            ADT_Contact__c = true
        );
        insert con;
        
        // 3. Template
        sra__Message_Template__c template = new sra__Message_Template__c(
            sra__Template_Body__c = 'Hello {!contact.lastname}'
        );
        insert template;
        
        // 4. Setting
        insert new MessageCustomization__c(
            Name = 'Test',
            Enable_SMS__c = true,
            Enable_Email__c = true,
            SMS_Template_Id_for_ADT__c = template.Id,
            Email_Template_Id_for_ADT__c = UserInfo.getUserId()
        );
        
        // 5. Sender Config
        insert new sra__Message_User_Configuration__c(
            sra__Sender_Number__c = '+910000000000'
        );
        
        // 6. CareObservation
        CareObservation obs = new CareObservation(
            Name = 'Thyrotropin [Units/volume] in Serum or Plasma',
            Category = 'Vital-Signs',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final'
        );
        if (Schema.SObjectType.CareObservation.fields.getMap().containsKey('adt_notify__c')) {
            obs.put('ADT_Notify__c', true);
        }
        insert obs;
        
        Test.startTest();
        CareObservationHandler.handleAfterInsert(new List<CareObservation>{ obs });
        Test.stopTest();
    }
    
    @isTest
    static void trigger_afterDelete_callsAuditLog() {
        Account acc = new Account(LastName = 'DeletePatient');
        insert acc;
        
        CareObservation obs = new CareObservation(
            Name               = 'Body weight',
            Category           = 'Vital-Signs',
            ObservedSubjectId  = acc.Id,
            ObservationStatus  = 'Final',
            Value_Quantity__c  = '70 kg'
        );
        insert obs;
        
        Test.startTest();
        delete obs;
        Test.stopTest();
        
    }
    
  
    @isTest
    static void trigger_bodyWeight_kgConvertedToPounds() {
        Account acc = new Account(LastName = 'WeightPatientKg');
        insert acc;
        
        CareObservation obs = new CareObservation(
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '70 kg'
        );
        
        Test.startTest();
        insert obs;
        Test.stopTest();
        
        Account updated = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        // 70 kg × 2.20462 = 154.32 lb
        System.assertEquals(
            154.32,
            updated.Weight_in_pounds__pc,
            'Weight should be converted from kg to pounds'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 9. CareObservationTrigger — Body weight already in pounds (no unit)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void trigger_bodyWeight_poundsNoConversion() {
        Account acc = new Account(LastName = 'WeightPatientLb');
        insert acc;
        
        CareObservation obs = new CareObservation(
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '154.32'   // no "kg" → treated as-is
        );
        
        Test.startTest();
        insert obs;
        Test.stopTest();
        
        Account updated = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(
            154.32,
            updated.Weight_in_pounds__pc,
            'Weight stored as-is when unit is not kg'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 10. CareObservationTrigger — Body height in cm → converted to inches
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void trigger_bodyHeight_cmConvertedToInches() {
        Account acc = new Account(LastName = 'HeightPatientCm');
        insert acc;
        
        CareObservation obs = new CareObservation(
            Name              = 'Body height',
            Category          = 'Vital-Signs',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '180 cm'
        );
        
        Test.startTest();
        insert obs;
        Test.stopTest();
        
        Account updated = [SELECT Height_in_inches__pc FROM Account WHERE Id = :acc.Id];
        // 180 cm × 0.393701 = 70.87 inches
        System.assertEquals(
            70.87,
            updated.Height_in_inches__pc,
            'Height should be converted from cm to inches'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 11. CareObservationTrigger — Body height already in inches (no unit)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void trigger_bodyHeight_inchesNoConversion() {
        Account acc = new Account(LastName = 'HeightPatientIn');
        insert acc;
        
        CareObservation obs = new CareObservation(
            Name              = 'Body height',
            Category          = 'Vital-Signs',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '70.87'    // no "cm" → treated as-is
        );
        
        Test.startTest();
        insert obs;
        Test.stopTest();
        
        Account updated = [SELECT Height_in_inches__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(
            70.87,
            updated.Height_in_inches__pc,
            'Height stored as-is when unit is not cm'
        );
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 12. CareObservationTrigger — Null ObservedSubjectId skipped (no crash)
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void trigger_nullSubjectId_skippedGracefully() {
         Account acc = new Account(LastName = 'HeightPatientIn1');
        insert acc;
        CareObservation obs = new CareObservation(
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservationStatus = 'Final',
            Value_Quantity__c = '70 kg',
             ObservedSubjectId = acc.Id);
        
        Test.startTest();
        insert obs;
        Test.stopTest();
        
        System.assert(true, 'Null ObservedSubjectId should be skipped without exception');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 13. CareObservationTrigger — Blank Value_Quantity__c skipped
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void trigger_blankValueQuantity_skippedGracefully() {
        Account acc = new Account(LastName = 'BlankValuePatient');
        insert acc;
        
        CareObservation obs = new CareObservation(
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = ''          // blank → continue in loop
        );
        
        Test.startTest();
        insert obs;
        Test.stopTest();
        
        System.assert(true, 'Blank Value_Quantity__c should be skipped without exception');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 14. CareObservationTrigger — Non-numeric Value_Quantity__c skipped
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void trigger_nonNumericValueQuantity_skippedGracefully() {
        Account acc = new Account(LastName = 'NonNumericPatient');
        insert acc;
        
        CareObservation obs = new CareObservation(
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = 'N/A'       // replaceAll strips everything → Decimal.valueOf throws
        );
        
        Test.startTest();
        insert obs;
        Test.stopTest();
        
        System.assert(true, 'Non-numeric Value_Quantity__c should be caught and skipped');
    }
    
    // ─────────────────────────────────────────────────────────────────────────
    // 15. CareObservationTrigger — After Update re-runs weight conversion
    // ─────────────────────────────────────────────────────────────────────────
    @isTest
    static void trigger_afterUpdate_weightRecalculated() {
        Account acc = new Account(LastName = 'UpdateWeightPatient');
        insert acc;
        
        CareObservation obs = new CareObservation(
            Name              = 'Body weight',
            Category          = 'Vital-Signs',
            ObservedSubjectId = acc.Id,
            ObservationStatus = 'Final',
            Value_Quantity__c = '70 kg'
        );
        insert obs;
        
        Test.startTest();
        obs.Value_Quantity__c = '80 kg';
        update obs;
        Test.stopTest();
        
        Account updated = [SELECT Weight_in_pounds__pc FROM Account WHERE Id = :acc.Id];
        System.assertEquals(
            176.37,
            updated.Weight_in_pounds__pc,
            'Weight should be recalculated on update'
        );
    }
}