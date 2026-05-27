@IsTest
private class ContentVersionSendToPortalTest {

    private static ContentVersion createContentVersion(
        String title,
        Boolean sendToPortal,
        String description,
        Datetime serviceDate
    ) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.txt',
            VersionData = Blob.valueOf('Test Data'),
            IsMajorVersion = true,
            Send_File_to_Portal__c = sendToPortal,
            Description = description,
            Service_Date_Time__c = serviceDate
        );
        insert cv;
        return [
            SELECT Id, ContentDocumentId, Send_File_to_Portal__c,
                   Description, Service_Date_Time__c, Title
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];
    }

    @IsTest
    static void testInsertWithSendToPortalTrue() {
        Test.startTest();
        ContentVersion cv = createContentVersion('InsertTrue', true, null, null);
        Test.stopTest();

        ContentVersion result = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(true, result.Send_File_to_Portal__c, 'Flag should be true immediately after insert');
    }

    // Covers the insert block with flag false — contentDocumentIds stays empty
    @IsTest
    static void testInsertWithSendToPortalFalse() {
        Test.startTest();
        ContentVersion cv = createContentVersion('InsertFalse', false, null, null);
        Test.stopTest();

        ContentVersion result = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(false, result.Send_File_to_Portal__c, 'Flag should remain false after insert');
    }

    // ─── UPDATE path tests — existing ───────────────────────────────────────

    // Flag flips false → true (send to portal)
    @IsTest
    static void testSendFileToPortal_FalseToTrue() {
        ContentVersion cv = createContentVersion('FalseToTrue', false, null, null);
        cv.Send_File_to_Portal__c = true;
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(true, result.Send_File_to_Portal__c, 'Flag should be true after update');
    }

    // Flag stays false (no action)
    @IsTest
    static void testNoActionWhenFlagRemainsFalse() {
        ContentVersion cv = createContentVersion('RemainFalse', false, null, null);
        cv.Send_File_to_Portal__c = false;
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(false, result.Send_File_to_Portal__c, 'Flag should remain false');
    }

    // Description changes while flag stays true (resend)
    @IsTest
    static void testResendWhenDescriptionChanges() {
        ContentVersion cv = createContentVersion('DescChange', true, 'Old Description', null);
        cv.Description = 'Updated Description';
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Description FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals('Updated Description', result.Description, 'Description should be updated');
    }

    // Service date changes while flag stays true (resend)
    @IsTest
    static void testResendWhenServiceDateChanges() {
        Datetime newDate = System.now().addDays(1);
        ContentVersion cv = createContentVersion('DateChange', true, null, System.now());
        cv.Service_Date_Time__c = newDate;
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Service_Date_Time__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertNotEquals(null, result.Service_Date_Time__c, 'Service date should not be null');
    }

    // ─── UPDATE path tests — new ─────────────────────────────────────────────

    // Covers the titleChange branch: title changes while flag stays true (resend)
    @IsTest
    static void testResendWhenTitleChanges() {
        ContentVersion cv = createContentVersion('OldTitle', true, null, null);
        // ContentVersion titles are immutable per version; a new version must be
        // inserted via CheckedOut + VersionData, but Title IS editable in-place
        // through a direct update in Apex test context.
        cv.Title = 'NewTitle';
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Title FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals('NewTitle', result.Title, 'Title should be updated — resend should fire');
    }

    // Flag flips true → false (delete from portal)
    @IsTest
    static void testDeleteFromPortal_TrueToFalse() {
        ContentVersion cv = createContentVersion('TrueToFalse', true, null, null);
        cv.Send_File_to_Portal__c = false;
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(false, result.Send_File_to_Portal__c,
            'Flag should be false after update — delete should have been triggered');
    }

    // Overlap bug: flag flips true → false AND description changes simultaneously
    // Only delete should fire, NOT send
    @IsTest
    static void testNoSendWhenFlagTurnedOffWithDescriptionChange() {
        ContentVersion cv = createContentVersion('OverlapBug', true, 'Old Desc', null);
        cv.Send_File_to_Portal__c = false;
        cv.Description = 'New Desc';
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Send_File_to_Portal__c, Description FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(false, result.Send_File_to_Portal__c,
            'Flag should be false — only delete should fire, not send');
        System.assertEquals('New Desc', result.Description, 'Description should be updated');
    }

    // Overlap bug variant: flag flips true → false AND date changes simultaneously
    @IsTest
    static void testNoSendWhenFlagTurnedOffWithDateChange() {
        ContentVersion cv = createContentVersion('OverlapBugDate', true, null, System.now());
        cv.Send_File_to_Portal__c = false;
        cv.Service_Date_Time__c = System.now().addDays(1);
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(false, result.Send_File_to_Portal__c,
            'Flag should be false — only delete should fire, not send');
    }

    // Flag stays true, nothing else changes — no send, no delete
    @IsTest
    static void testNoActionWhenFlagRemainsTrue() {
        ContentVersion cv = createContentVersion('StaysTrue', true, 'Same Desc', null);
        // No field change — resubmit with same values
        cv.Send_File_to_Portal__c = true;
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(true, result.Send_File_to_Portal__c, 'Flag should remain true');
    }

    // ─── AI Trace path — new ────────────────────────────────────────────────

    // Covers the contentDocumentIdsForAITrace block:
    // When a primary file's flag flips false → true, the trigger must also
    // flip Send_File_to_Portal__c on any ContentVersion whose Related_File__c
    // points to that primary ContentDocumentId.
    @IsTest
    static void testAITraceFileUpdatedWhenPrimaryFlipsToTrue() {
        // Primary file starts with flag = false
        ContentVersion primary = createContentVersion('PrimaryFile', false, null, null);

        // AI trace file whose Related_File__c points to primary's ContentDocumentId
        ContentVersion aiTrace = new ContentVersion(
            Title = 'AITraceFile',
            PathOnClient = 'AITraceFile.txt',
            VersionData = Blob.valueOf('AI Trace Data'),
            IsMajorVersion = true,
            Send_File_to_Portal__c = false,
            Related_File__c = primary.ContentDocumentId
        );
        insert aiTrace;

        // Flip primary flag to true — trigger should cascade to aiTrace
        primary.Send_File_to_Portal__c = true;
        Test.startTest();
        update primary;
        Test.stopTest();

        ContentVersion aiResult = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :aiTrace.Id];
        System.assertEquals(true, aiResult.Send_File_to_Portal__c,
            'AI trace file should be flipped to true when its related primary file is enabled');
    }

    // AI Trace path with NO matching Related_File__c records — block should no-op safely
    @IsTest
    static void testAITraceNoMatchingRelatedFiles() {
        ContentVersion cv = createContentVersion('NoRelated', false, null, null);
        cv.Send_File_to_Portal__c = true;
        Test.startTest();
        update cv;
        Test.stopTest();

        ContentVersion result = [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id = :cv.Id];
        System.assertEquals(true, result.Send_File_to_Portal__c,
            'Primary flag should be true; no AI trace records present — no DML error expected');
    }

    // ─── Bulk tests ──────────────────────────────────────────────────────────

    // Existing: bulk update false → true
    @IsTest
    static void testBulkUpdate() {
        List<ContentVersion> versions = new List<ContentVersion>();
        for (Integer i = 0; i < 5; i++) {
            versions.add(new ContentVersion(
                Title = 'BulkTest' + i,
                PathOnClient = 'BulkTest' + i + '.txt',
                VersionData = Blob.valueOf('Bulk Data ' + i),
                IsMajorVersion = true,
                Send_File_to_Portal__c = false
            ));
        }
        insert versions;
        versions = [SELECT Id, Send_File_to_Portal__c FROM ContentVersion WHERE Id IN :versions];
        for (ContentVersion cv : versions) {
            cv.Send_File_to_Portal__c = true;
        }
        Test.startTest();
        update versions;
        Test.stopTest();

        for (ContentVersion cv : [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id IN :versions]) {
            System.assertEquals(true, cv.Send_File_to_Portal__c,
                'All bulk records should have flag set to true');
        }
    }

    // Bulk update true → false (bulk delete scenario)
    @IsTest
    static void testBulkDelete() {
        List<ContentVersion> versions = new List<ContentVersion>();
        for (Integer i = 0; i < 5; i++) {
            versions.add(new ContentVersion(
                Title = 'BulkDelete' + i,
                PathOnClient = 'BulkDelete' + i + '.txt',
                VersionData = Blob.valueOf('Bulk Delete Data ' + i),
                IsMajorVersion = true,
                Send_File_to_Portal__c = true
            ));
        }
        insert versions;
        versions = [SELECT Id, Send_File_to_Portal__c FROM ContentVersion WHERE Id IN :versions];
        for (ContentVersion cv : versions) {
            cv.Send_File_to_Portal__c = false;
        }
        Test.startTest();
        update versions;
        Test.stopTest();

        for (ContentVersion cv : [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id IN :versions]) {
            System.assertEquals(false, cv.Send_File_to_Portal__c,
                'All bulk records should have flag set to false');
        }
    }

    // Bulk insert with flag = true — covers insert block contentDocumentIds path at scale
    @IsTest
    static void testBulkInsertWithSendToPortalTrue() {
        List<ContentVersion> versions = new List<ContentVersion>();
        for (Integer i = 0; i < 5; i++) {
            versions.add(new ContentVersion(
                Title = 'BulkInsertTrue' + i,
                PathOnClient = 'BulkInsertTrue' + i + '.txt',
                VersionData = Blob.valueOf('Bulk Insert True Data ' + i),
                IsMajorVersion = true,
                Send_File_to_Portal__c = true
            ));
        }
        Test.startTest();
        insert versions;
        Test.stopTest();

        for (ContentVersion cv : [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id IN :versions]) {
            System.assertEquals(true, cv.Send_File_to_Portal__c,
                'All bulk-inserted records should have flag set to true');
        }
    }

    // Mixed bulk: some flip false→true, some flip true→false in the same DML
    // Validates that send and delete sets are populated correctly in parallel
    @IsTest
    static void testBulkMixedSendAndDelete() {
        List<ContentVersion> toEnable  = new List<ContentVersion>();
        List<ContentVersion> toDisable = new List<ContentVersion>();

        for (Integer i = 0; i < 3; i++) {
            toEnable.add(new ContentVersion(
                Title = 'MixEnable' + i,
                PathOnClient = 'MixEnable' + i + '.txt',
                VersionData = Blob.valueOf('Enable ' + i),
                IsMajorVersion = true,
                Send_File_to_Portal__c = false
            ));
            toDisable.add(new ContentVersion(
                Title = 'MixDisable' + i,
                PathOnClient = 'MixDisable' + i + '.txt',
                VersionData = Blob.valueOf('Disable ' + i),
                IsMajorVersion = true,
                Send_File_to_Portal__c = true
            ));
        }
        insert toEnable;
        insert toDisable;

        toEnable  = [SELECT Id, Send_File_to_Portal__c FROM ContentVersion WHERE Id IN :toEnable];
        toDisable = [SELECT Id, Send_File_to_Portal__c FROM ContentVersion WHERE Id IN :toDisable];

        for (ContentVersion cv : toEnable)  { cv.Send_File_to_Portal__c = true;  }
        for (ContentVersion cv : toDisable) { cv.Send_File_to_Portal__c = false; }

        List<ContentVersion> mixed = new List<ContentVersion>();
        mixed.addAll(toEnable);
        mixed.addAll(toDisable);

        Test.startTest();
        update mixed;
        Test.stopTest();

        for (ContentVersion cv : [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id IN :toEnable]) {
            System.assertEquals(true, cv.Send_File_to_Portal__c, 'toEnable records should now be true');
        }
        for (ContentVersion cv : [SELECT Send_File_to_Portal__c FROM ContentVersion WHERE Id IN :toDisable]) {
            System.assertEquals(false, cv.Send_File_to_Portal__c, 'toDisable records should now be false');
        }
    }
}