trigger MemberPayloadTrigger on Member_Payload__c (after insert) {
    List<Member_Payload__c> validRecords = new List<Member_Payload__c>();
    for (Member_Payload__c rec : Trigger.new) {
        if (String.isNotBlank(rec.Payload_JSON__c)) {
            validRecords.add(rec);
        }
    }
    if (!validRecords.isEmpty()) {
        MemberPayloadInsert.handle(validRecords);
    }
}