import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import upsertCustomer from '@salesforce/apex/QuickBooksCustomerService.upsertCustomer';

export default class QuickbooksCustomerSync extends LightningElement {
    recordId;
    hasRun = false;

    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (!pageRef || this.hasRun) {
            return;
        }

        this.recordId =
            pageRef.state?.recordId ||
            pageRef.attributes?.recordId;

        if (!this.recordId) {
            this.showToast('Error', 'Account context not found', 'error');
            this.closeAction();
            return;
        }

        this.hasRun = true;
        this.syncCustomer();
    }

    async syncCustomer() {
        try {
            console.log('recordId before call = ', this.recordId);
            console.log(
                JSON.stringify({
                    accountId: this.recordId
                })
            );

            await upsertCustomer({
                accountId: this.recordId
            });

            this.showToast(
                'Success',
                'Customer synced to QuickBooks successfully.',
                'success'
            );
        } catch (error) {
            this.showToast(
                'Error',
                error?.body?.message || error?.message || 'Something went wrong.',
                'error'
            );
        } finally {
            this.closeAction();
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}