trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert ) {

    Set<Id> caseIds = new Set<Id>();

    for (ContentDocumentLink cdl : Trigger.new) {
        if (cdl.LinkedEntityId != null &&
            cdl.LinkedEntityId.getSObjectType() == Case.SObjectType) {
            caseIds.add(cdl.LinkedEntityId);
        }
    }

    if (caseIds.isEmpty()) return;

    Set<Id> portalCaseIds = new Set<Id>();

    for (Case c : [
        SELECT Id
        FROM Case
        WHERE Id IN :caseIds
        AND Case_Type__c = 'Portal Messages'
        AND AccountId != null
        AND Account.IsPersonAccount = true
    ]) {
        portalCaseIds.add(c.Id);
    }

    if (portalCaseIds.isEmpty()) return;
    CaseSalesforceRecord.createPublicLinksSync(portalCaseIds);
    CaseSalesforceRecord.sendToThirdPartyFuture(
        portalCaseIds,
        'UPDATE',
        true
    );
}