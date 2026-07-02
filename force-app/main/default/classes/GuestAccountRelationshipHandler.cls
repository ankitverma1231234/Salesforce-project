public class GuestAccountRelationshipHandler {

    public class GuestAHRRequest {
        public Id              guestAccountId;   
        public List<Id>        memberAccountIds;

        public GuestAHRRequest(Id guestAccountId, List<Id> memberAccountIds) {
            this.guestAccountId   = guestAccountId;
            this.memberAccountIds = memberAccountIds;
        }
    }

    public static void createAHRRecords(List<GuestAHRRequest> requests) {
        if (requests == null || requests.isEmpty()) return;

        List<Account_Head_Relationship__c> ahrToInsert =
            new List<Account_Head_Relationship__c>();

        for (GuestAHRRequest req : requests) {
            if (req.guestAccountId == null) continue;
            if (req.memberAccountIds == null || req.memberAccountIds.isEmpty()) continue;

            for (Id memberAccId : req.memberAccountIds) {
                if (memberAccId == null) continue;

                ahrToInsert.add(new Account_Head_Relationship__c(
                    Member_Account__c             = req.guestAccountId,
                    Authorized_Account_Access__c  = memberAccId,
                    Request_Access__c = true
                ));
            }
        }

        if (!ahrToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(ahrToInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug('AHR insert failed [' + i + ']: '
                        + results[i].getErrors()[0].getMessage());
                }
            }
        }
    }
}