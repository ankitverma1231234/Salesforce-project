global without sharing class DocFlowReminderScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        System.enqueueJob(new DocFlowReminderDispatcher());
    }
}