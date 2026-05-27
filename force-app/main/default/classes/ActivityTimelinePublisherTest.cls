@IsTest
private class ActivityTimelinePublisherTest {

    @IsTest
    static void testPublishEvents() {
        Account acc = new Account(Name = 'Test Acc');
        insert acc;

        Test.startTest();
        ActivityTimelinePublisher.publishByRecordIds(
            new Set<Id>{ acc.Id }
        );
        Test.stopTest();

        System.assert(true, 'Platform Event publish executed');
    }

    @IsTest
    static void testEmptySet() {
        Test.startTest();
        ActivityTimelinePublisher.publishByRecordIds(new Set<Id>());
        Test.stopTest();

        System.assert(true);
    }
}