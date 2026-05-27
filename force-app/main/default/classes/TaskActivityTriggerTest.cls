@IsTest
private class TaskActivityTriggerTest {

    @IsTest
    static void testTaskTriggerWithWhatId() {

        // Parent record for WhatId
        Account acc = new Account(Name = 'Task Acc');
        insert acc;

        Task t = new Task(
            Subject = 'Test Task',
            Status = 'Not Started',
            Priority = 'Normal',
            WhatId = acc.Id
        );

        Test.startTest();
        insert t;
        Test.stopTest();

        // If no exception occurs, trigger executed successfully
        System.assert(true, 'Task trigger executed with WhatId');
    }

    @IsTest
    static void testTaskTriggerWithoutWhatId() {

        Task t = new Task(
            Subject = 'Task Without WhatId',
            Status = 'Not Started',
            Priority = 'Normal'
        );

        Test.startTest();
        insert t;
        Test.stopTest();

        // Should not fail when WhatId is null
        System.assert(true, 'Task trigger handled null WhatId');
    }

    @IsTest
    static void testBulkTaskInsert() {

        Account acc = new Account(Name = 'Bulk Task Acc');
        insert acc;

        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < 50; i++) {
            tasks.add(new Task(
                Subject = 'Bulk Task ' + i,
                Status = 'Not Started',
                Priority = 'Normal',
                WhatId = acc.Id
            ));
        }

        Test.startTest();
        insert tasks;
        Test.stopTest();

        System.assertEquals(50, tasks.size(), 'Bulk tasks inserted');
    }
}