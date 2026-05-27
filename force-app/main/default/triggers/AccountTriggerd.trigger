trigger AccountTriggerd on Account (before delete) {
  /*  Map<Id, String> accountIdToMetriportPatientId = new Map<Id, String>();

    for (Account acc : Trigger.old) {
        if (String.isNotBlank(acc.Metriport_Patient_Id__c)) {
            accountIdToMetriportPatientId.put(acc.Id, acc.Metriport_Patient_Id__c);
        }
    }

    if (!accountIdToMetriportPatientId.isEmpty()) {
        MetriportPatientDeleteService.deleteMetriportPatients(accountIdToMetriportPatientId);
    } */
}