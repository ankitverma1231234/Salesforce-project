public with sharing class CaseController {
    @AuraEnabled(cacheable=true)
    public static List<Case> getCases(Id accountId) {
        return [
            SELECT Id, CaseNumber, Subject, Status, Priority, CreatedDate
            FROM Case
            WHERE AccountId = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }
}