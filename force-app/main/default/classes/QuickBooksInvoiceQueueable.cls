public class QuickBooksInvoiceQueueable implements Queueable, Database.AllowsCallouts {

    private Id oppId;

    public QuickBooksInvoiceQueueable(Id oppId) {
        this.oppId = oppId;
    }

    public void execute(QueueableContext ctx) {
        try {
            // Step 1 — load Opportunity + Account + OLIs
            Opportunity opp = fetchOpportunity(oppId);

            // Step 2 — validate customer exists in QB
            if (String.isBlank(opp.Account.QB_Customer_Id__c)) {
                QuickBooksCustomerService.CustomerResponse custResult =
                    QuickBooksCustomerService.upsertCustomer(opp.AccountId);
                if (!custResult.success) {
                    logError(oppId, 'Customer sync failed before invoice creation: '
                             + custResult.errorMessage, null);
                    return;
                }
                // reload opp with updated account
                opp = fetchOpportunity(oppId);
            }

            // Step 3 — upsert invoice in QB
            QuickBooksInvoiceService.InvoiceResponse invoiceResult =
                QuickBooksInvoiceService.upsertInvoice(opp);

            if (!invoiceResult.success) {
                logError(oppId, 'Invoice creation failed: ' + invoiceResult.errorMessage,
                         invoiceResult.statusCode);
                return;
            }

            // Step 4 — write QB Invoice Id back to Opportunity
            update new Opportunity(
                Id                = oppId,
                QB_Invoice_Id__c  = invoiceResult.qbInvoiceId
            );

            // Step 5 — chain next queueable to fetch + store PDF
            System.enqueueJob(
                new QuickBooksInvoicePdfQueueable(oppId, invoiceResult.qbInvoiceId)
            );

        } catch (Exception e) {
            logError(oppId, e.getMessage(), null);
        }
    }

    // ── SOQL ─────────────────────────────────────────────────────────────────

    private static Opportunity fetchOpportunity(Id oppId) {
        return [
            SELECT  Id, Name, CloseDate, Description,
                    AccountId,
                    Account.QB_Customer_Id__c,
                    QB_Invoice_Id__c,
                    (
                        SELECT  Id, Quantity, UnitPrice, TotalPrice,
                                Description,
                                Product2.Name,Product2.Description,
                                Product2.QB_Item_Id__c
                        FROM    OpportunityLineItems
                    )
            FROM    Opportunity
            WHERE   Id = :oppId
            LIMIT   1
        ];
    }

    private static void logError(Id oppId, String message, Integer statusCode) {
        try {
            insert new Error_Log__c(
                Record_External_Id__c = (String) oppId,
                Error_Message__c      = message,
                Context__c            = 'QuickBooksInvoiceQueueable.execute',
                Stack_Trace__c        = 'OpportunityId: ' + oppId
                                      + ' | StatusCode: ' + statusCode
            );
        } catch (Exception e) {
            System.debug('Error log insert failed: ' + e.getMessage());
        }
    }
}