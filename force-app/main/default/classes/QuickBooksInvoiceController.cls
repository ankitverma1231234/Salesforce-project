/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : QuickbookInvoiceController
 * Author          : <YourName>
 * Created Date    : Jun 16, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 16, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 16, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class QuickBooksInvoiceController {
    @AuraEnabled
    public static void createInvoice(Id opportunityId) {
        Opportunity opp = [
            SELECT Id, StageName, QB_Invoice_Id__c
            FROM   Opportunity
            WHERE  Id = :opportunityId
            LIMIT  1
        ];
        System.enqueueJob(new QuickBooksInvoiceQueueable(opp.Id));
    }
}