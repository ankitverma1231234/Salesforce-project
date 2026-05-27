/**
* @File Name : CreateCaseFromAccountController.cls
* @Description :
* @Author :
* @Last Modified By :
* @Last Modified On : December 29, 2025
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | December 29, 2025 |   | Initial Version
**/

public with sharing class CreateCaseFromAccountController {

    @AuraEnabled(cacheable=true)
    public static Account getAccount(Id accountId) {
        return [
            SELECT Id, Name
            FROM Account
            WHERE Id = :accountId and IsPersonAccount=true
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static Id createCase(Id accountId) {
        Case c = new Case();
        c.AccountId = accountId;
        c.Subject   = 'Case created from Account';
        c.Status    = 'New';
        c.Origin    = 'Web';

        insert c;
        return c.Id;
    }
}