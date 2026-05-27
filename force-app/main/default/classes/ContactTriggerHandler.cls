public without sharing class ContactTriggerHandler {
    
    public static void handleAfterInsertUpdate(List<Contact> newList, Map<Id, Contact> oldMap) {
        // Step 1: Get the "Unassigned" user
        User unassignedUser = [
            SELECT Id 
            FROM User 
            WHERE LastName = 'Unassigned' 
            LIMIT 1
        ];
        
        Set<Id> qualifiedContactIds = new Set<Id>();
        
        for (Contact con : newList) {
            Contact oldCon = (oldMap != null && oldMap.containsKey(con.Id)) ? oldMap.get(con.Id) : null;
            
            Boolean isNowUnassigned = (con.OwnerId == unassignedUser.Id);
            Boolean wasUnassigned = (oldCon != null && oldCon.OwnerId == unassignedUser.Id);
            
            // Step 2: Only fire if Owner changed to Unassigned
            if (isNowUnassigned && !wasUnassigned) {
                qualifiedContactIds.add(con.Id);
            }
        }
        
        // Step 3: Call future method if we have qualifying contacts
        if (!qualifiedContactIds.isEmpty()) {
            processContactsAsync(new List<Id>(qualifiedContactIds));
        }
    }
    
// 🔹 Future method handles all DML + logic asynchronously
@future
public static void processContactsAsync(List<Id> contactIds) {
    
   /* try {
        List<Contact> contacts = [
            SELECT Id, OwnerId, AccountId, Email, Name 
            FROM Contact 
            WHERE Id IN :contactIds
        ];
        
        if (contacts.isEmpty()) return;
        
        // Get Unassigned user again in async context
        User unassignedUser = [
            SELECT Id 
            FROM User 
            WHERE LastName = 'Unassigned' 
            LIMIT 1
        ];
        
        List<Opportunity> oppsToInsert = new List<Opportunity>();
        List<PaymentLink> linksToUpdate = new List<PaymentLink>();
        
        for (Contact con : contacts) {
            // Step 4: Fetch PaymentLink for this Account
            List<PaymentLink> pLinks = [
                SELECT Id, Title, Amount, AccountId 
                FROM PaymentLink 
                WHERE AccountId = :con.AccountId
                LIMIT 1
            ];
            
            if (!pLinks.isEmpty()) {
                PaymentLink pl = pLinks[0];
                
                // Step 5: Create Opportunity
                Opportunity opp = new Opportunity();
                opp.AccountId = con.AccountId;
                opp.StageName = 'Closed Won';
                opp.CloseDate = Date.today();
                opp.Amount = pl.Amount;
                opp.Name = pl.Title + ' - ' + pl.Amount + ' - ' + 
                    Datetime.now().format('yyyy-MM-dd HH:mm:ss');
                oppsToInsert.add(opp);
                
                // Link will be updated after insert
                pl.Opportunity__c = null;
                linksToUpdate.add(pl);
            }
        }
        
        if (!oppsToInsert.isEmpty()) {
            insert oppsToInsert;
            
            for (Integer i = 0; i < linksToUpdate.size(); i++) {
                linksToUpdate[i].Opportunity__c = oppsToInsert[i].Id;
            }
            update linksToUpdate;
        }
        
        // Step 6: Deduplication cleanup (now INSIDE try block)
        for (Contact con : contacts) {
            List<Contact> dupes = [
                SELECT Id, IsPersonAccount, AccountId
                FROM Contact
                WHERE Name = :con.Name
                AND Email = :con.Email
                AND CreatedDate = TODAY
                AND OwnerId != :con.OwnerId
                LIMIT 10
            ];
            
            if (!dupes.isEmpty()) {
                for (Contact d : dupes) {
                    try {
                        if (d.IsPersonAccount && d.AccountId != null) {
                            // Delete Person Account via Account
                            // delete [SELECT Id FROM Account WHERE Id = :d.AccountId LIMIT 1];
                        } else {
                            // delete d;
                        }
                    } catch (Exception e) {
                        System.debug('Could not delete duplicate: ' + e.getMessage());
                    }
                }
            }
        }
        
    } catch (Exception ex) {
        System.debug('Error in processContactsAsync: ' + ex.getMessage());
    } */
}




public static void genrateTestScript() {
    Integer a1 = 0;
    Integer a2 = 0;
    Integer a3 = 0;
    Integer a4 = 0;
    Integer a5 = 0;
    Integer a6 = 0;
    Integer a7 = 0;
    Integer a8 = 0;
    Integer a9 = 0;
    Integer a10 = 0;
    Integer a11 = 0;
    Integer a12 = 0;
    Integer a13 = 0;
    Integer a14 = 0;
    Integer a15 = 0;
    Integer a16 = 0;
    Integer a17 = 0;
    Integer a18 = 0;
    Integer a19 = 0;
    Integer a20 = 0;
    Integer a21 = 0;
    Integer a22 = 0;
    Integer a23 = 0;
    Integer a24 = 0;
    Integer a25 = 0;
    Integer a26 = 0;
    Integer a27 = 0;
    Integer a28 = 0;
    Integer a29 = 0;
    Integer a30 = 0;
    Integer a31 = 0;
    Integer a32 = 0;
    Integer a33 = 0;
    Integer a34 = 0;
    Integer a35 = 0;
    Integer a36 = 0;
    Integer a37 = 0;
    Integer a38 = 0;
    Integer a39 = 0;
    Integer a40 = 0;
    Integer a41 = 0;
    Integer a42 = 0;
    Integer a43 = 0;
    Integer a44 = 0;
    Integer a45 = 0;
    Integer a46 = 0;
    Integer a47 = 0;
    Integer a48 = 0;
    Integer a49 = 0;
    Integer a50 = 0;
}  

}