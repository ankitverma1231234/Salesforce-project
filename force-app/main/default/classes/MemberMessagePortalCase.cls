public class MemberMessagePortalCase {
    // Fetch Person Account & Contact
    @AuraEnabled(cacheable=true)
    public static Account getPersonAccount(Id accountId) {
        return [
            SELECT Id, Name, PersonContactId,
            PersonContact.Name
            FROM Account
            WHERE Id = :accountId
            AND IsPersonAccount = true
            LIMIT 1
        ];
    }
    
    // Create Case
    @AuraEnabled
    public static Id createCase(
        String subject,
        String description,
        Id accountId,
        Id contactId
    ) {
        Case c = new Case();
        c.Subject = subject;
        c.Description = description;
        c.AccountId = accountId;
        c.ContactId = contactId;
        c.Case_Type__c = 'Portal Messages';
        c.Status = 'New';
        
        insert c;
        return c.Id;
    }
@AuraEnabled
public static void linkFilesToCase(Id caseId, List<Id> documentIds) {

    List<ContentDocumentLink> links = new List<ContentDocumentLink>();

    for (Id docId : documentIds) {
        links.add(new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = caseId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        ));
    }

    insert links;
}
}