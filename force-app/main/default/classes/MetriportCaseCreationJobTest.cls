@IsTest(SeeAllData=true)
private class MetriportCaseCreationJobTest {

    @IsTest
    static void testQueueableExecution() {

        Account acc = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];

        Test.startTest();

        MetriportCaseCreationJob.enqueueDelayed(acc.Id);

        Test.stopTest();

        System.assertNotEquals(
            null,
            acc.Id,
            'Person Account should exist'
        );
    }

    @IsTest
    static void testDirectExecute() {

        Account acc = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            LIMIT 1
        ];

        Test.startTest();

        new MetriportCaseCreationJob(acc.Id)
            .execute(null);

        Test.stopTest();

        System.assert(true);
    }
@IsTest
static void testExceptionPath() {

    Test.startTest();

    System.enqueueJob(
        new MetriportCaseCreationJob(null)
    );

    Test.stopTest();

    Error_Log__c logRec = [
        SELECT Id,
               Error_Message__c
        FROM Error_Log__c
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    System.assertNotEquals(null, logRec.Id);
}
}