public class OpportunityTriggerHandler {

    public static void handle(Map<Id, Opportunity> newMap, Map<Id, Opportunity> oldMap) {
        List<Id> eligibleOppIds = new List<Id>();

        for (Opportunity opp : newMap.values()) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            Boolean stageChangedToClosedWon = opp.StageName == 'Closed Won'
                                           && oldOpp.StageName != 'Closed Won';
            Boolean notAlreadySynced        = String.isBlank(opp.QB_Invoice_Id__c);

            if (stageChangedToClosedWon && notAlreadySynced) {
                eligibleOppIds.add(opp.Id);
            }
        }

        if (!eligibleOppIds.isEmpty()) {
            for (Id oppId : eligibleOppIds) {
                System.enqueueJob(new QuickBooksInvoiceQueueable(oppId));
            }
        }
    }
}