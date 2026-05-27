trigger DocFlowAnalyticsTrigger on Doc_Flow_Analytics__c (after insert, after update) {
    if (Trigger.isAfter) {
        DocFlowAnalyticsProcessor.handleAfter(Trigger.new, Trigger.oldMap);
    }
}