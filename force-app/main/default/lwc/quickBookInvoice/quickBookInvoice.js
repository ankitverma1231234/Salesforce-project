import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import createInvoice from '@salesforce/apex/QuickBooksInvoiceController.createInvoice';

export default class QuickbooksInvoiceSync extends LightningElement {
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
            this.showToast('Error', 'Opportunity context not found', 'error');
            this.closeAction();
            return;
        }

        this.hasRun = true;
        this.syncInvoice();
    }

    async syncInvoice() {
        try {
            await createInvoice({
                opportunityId: this.recordId
            });

            this.showToast(
                'Success',
                'Invoice queued successfully. PDF will be attached shortly.',
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
            new ShowToastEvent({ title, message, variant })
        );
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}