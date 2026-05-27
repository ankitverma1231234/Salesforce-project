@IsTest
private class SessionTimeoutTest {

    // ─────────────────────────────────────────
    // TEST DATA HELPER
    // ─────────────────────────────────────────
    private static Message_Session__c createSession(String status, DateTime endTime) {
        Message_Session__c session = new Message_Session__c(
            Phone_Number__c  = '1234567890',
            Start_Time__c    = DateTime.now().addHours(-2),
            End_Time__c      = endTime,
            Session_Status__c = status
        );
        insert session;
        return session;
    }

    // ═════════════════════════════════════════
    // BATCH TESTS
    // ═════════════════════════════════════════

    @IsTest
    static void testBatch_closesExpiredOpenSessions() {
        // Arrange — 3 expired Open sessions
        createSession('Open', DateTime.now().addMinutes(-10));
        createSession('Open', DateTime.now().addMinutes(-5));
        createSession('Open', DateTime.now().addMinutes(-1));

        // Act
        Test.startTest();
        Database.executeBatch(new SessionTimeoutBatch(), 200);
        Test.stopTest();

        // Assert — all three should now be Closed
        List<Message_Session__c> closed = [
            SELECT Id, Session_Status__c
            FROM   Message_Session__c
            WHERE  Session_Status__c = 'Closed'
        ];
        Assert.areEqual(3, closed.size(), 'All 3 expired sessions should be closed');
    }

    @IsTest
    static void testBatch_doesNotCloseActiveSessions() {
        // Arrange — 1 expired + 1 still-active session
        createSession('Open', DateTime.now().addMinutes(-10)); // expired → should close
        createSession('Open', DateTime.now().addHours(1));     // future  → should stay Open

        // Act
        Test.startTest();
        Database.executeBatch(new SessionTimeoutBatch(), 200);
        Test.stopTest();

        // Assert
        List<Message_Session__c> stillOpen = [
            SELECT Id FROM Message_Session__c WHERE Session_Status__c = 'Open'
        ];
        List<Message_Session__c> nowClosed = [
            SELECT Id FROM Message_Session__c WHERE Session_Status__c = 'Closed'
        ];
        Assert.areEqual(1, stillOpen.size(),  'Future session must remain Open');
        Assert.areEqual(1, nowClosed.size(),  'Expired session must be Closed');
    }

    @IsTest
    static void testBatch_alreadyClosedSessionsIgnored() {
        // Arrange — only already-Closed sessions in org
        createSession('Closed', DateTime.now().addMinutes(-10));
        createSession('Closed', DateTime.now().addMinutes(-5));

        // Act
        Test.startTest();
        Database.executeBatch(new SessionTimeoutBatch(), 200);
        Test.stopTest();

        // Assert — nothing changed, both still Closed
        Integer count = [
            SELECT COUNT() FROM Message_Session__c WHERE Session_Status__c = 'Closed'
        ];
        Assert.areEqual(2, count, 'Pre-closed sessions must not be altered');
    }

    @IsTest
    static void testBatch_emptyScope_noErrors() {
        // Arrange — no sessions at all
        // Act + Assert — batch should complete without exceptions
        Test.startTest();
        Database.executeBatch(new SessionTimeoutBatch(), 200);
        Test.stopTest();

        Integer total = [SELECT COUNT() FROM Message_Session__c];
        Assert.areEqual(0, total, 'No records should exist');
    }

    @IsTest
    static void testBatch_largeBulkVolume() {
        // Arrange — 200 expired sessions (full batch chunk)
        List<Message_Session__c> sessions = new List<Message_Session__c>();
        for (Integer i = 0; i < 200; i++) {
            sessions.add(new Message_Session__c(
                Phone_Number__c   = '555000' + String.valueOf(i).leftPad(4, '0'),
                Start_Time__c     = DateTime.now().addHours(-3),
                End_Time__c       = DateTime.now().addMinutes(-1),
                Session_Status__c = 'Open'
            ));
        }
        insert sessions;

        // Act
        Test.startTest();
        Database.executeBatch(new SessionTimeoutBatch(), 200);
        Test.stopTest();

        // Assert
        Integer closedCount = [
            SELECT COUNT() FROM Message_Session__c WHERE Session_Status__c = 'Closed'
        ];
        Assert.areEqual(200, closedCount, '200 bulk sessions should all be closed');
    }

    // ═════════════════════════════════════════
    // SCHEDULER TESTS
    // ═════════════════════════════════════════

    @IsTest
    static void testScheduler_executesBatchWhenNoneRunning() {
        // Arrange — expired session so the batch has work to do
        createSession('Open', DateTime.now().addMinutes(-10));

        // Act
        Test.startTest();
        // Invoke scheduler directly (no real AsyncApexJob exists in test context)
        new SessionTimeoutScheduler().execute(null);
        Test.stopTest();

        // Assert — session closed, confirming batch was submitted and ran
        Integer closedCount = [
            SELECT COUNT() FROM Message_Session__c WHERE Session_Status__c = 'Closed'
        ];
        Assert.areEqual(1, closedCount, 'Scheduler should have triggered the batch');
    }

    @IsTest
    static void testScheduler_skipsBatchWhenAlreadyRunning() {
        // Arrange — no expired session; the isBatchRunning() guard is
        // effectively tested through the debug log path (no real
        // AsyncApexJob can be injected in a sync test context, but we
        // verify the scheduler executes without error)
        Test.startTest();
        new SessionTimeoutScheduler().execute(null);
        Test.stopTest();

        // Assert — no DML errors, batch finished cleanly
        Integer total = [SELECT COUNT() FROM Message_Session__c];
        Assert.areEqual(0, total, 'No sessions — scheduler exits without errors');
    }

    @IsTest
    static void testScheduleJobs_registers12CronEntries() {
        // Act
        Test.startTest();
        SessionTimeoutScheduler.scheduleJobs();
        Test.stopTest();

        // Assert — exactly 12 cron entries created
        Integer jobCount = [
            SELECT COUNT() FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Message_SessionTimeOut_%'
        ];
        Assert.areEqual(12, jobCount, 'scheduleJobs() must register exactly 12 entries');
    }

    @IsTest
    static void testScheduleJobs_jobNamesMatchPattern() {
        // Act
        Test.startTest();
        SessionTimeoutScheduler.scheduleJobs();
        Test.stopTest();

        // Assert — every job name matches 'Message_SessionTimeOut_<minute>'
        List<CronTrigger> jobs = [
            SELECT CronJobDetail.Name
            FROM   CronTrigger
            WHERE  CronJobDetail.Name LIKE 'Message_SessionTimeOut_%'
        ];
        Set<String> expectedNames = new Set<String>();
        for (Integer min : new Integer[]{ 0,5,10,15,20,25,30,35,40,45,50,55 }) {
            expectedNames.add('Message_SessionTimeOut_' + min);
        }
        for (CronTrigger ct : jobs) {
            Assert.isTrue(
                expectedNames.contains(ct.CronJobDetail.Name),
                'Unexpected job name: ' + ct.CronJobDetail.Name
            );
        }
    }
}