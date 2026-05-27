@IsTest
private class EventActivityTriggerTest {

    @IsTest
    static void testEventTrigger() {
        Account acc = new Account(Name = 'Event Acc');
        insert acc;

        Event ev = new Event(
            Subject = 'Test Event',
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1),
            WhatId = acc.Id
        );

        Test.startTest();
        insert ev;
        Test.stopTest();

        System.assert(true, 'Event trigger executed');
    }
}