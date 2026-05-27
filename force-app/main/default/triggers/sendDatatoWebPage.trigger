trigger sendDatatoWebPage on CareObservation (after insert) {
    TriggerSettings__c setting = TriggerSettings__c.getInstance();
    if (setting == null || !setting.Care_Observation_Checkbox__c) return;

    VitalAPIHandler.sendData(Trigger.newMap.keySet());
}