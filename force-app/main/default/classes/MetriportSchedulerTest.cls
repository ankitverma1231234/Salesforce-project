@IsTest(SeeAllData=true)
private class MetriportSchedulerTest {

    @IsTest
    static void testSchedulerExecution() {

        Account acc = [
            SELECT Id, Metriport_Patient_Id__c
            FROM Account
            WHERE Metriport_Patient_Id__c != NULL
            LIMIT 1
        ];

        MetriportScheduler scheduler =
            new MetriportScheduler(
                acc.Metriport_Patient_Id__c
            );

        String cronExp = '0 0 0 1 1 ? 2099';

        Test.startTest();

        String jobId = System.schedule(
            'Test Metriport Scheduler Job',
            cronExp,
            scheduler
        );

        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }
}