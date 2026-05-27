import { LightningElement, api, track } from 'lwc';
import processRefund from '@salesforce/apex/StripeRefundController.processRefund';
import updateTransactionNotes from '@salesforce/apex/StripeRefundController.updateTransactionNotes';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class RefundButton extends LightningElement {
    @api recordId;
    @track notes = '';
    @track isModalOpen = false;

    @api invoke() {
        this.openModal();
    }

    openModal() {
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    handleSubmit() {
        this.updateNotesAndRefund();
    }

    updateNotesAndRefund() {
        updateTransactionNotes({ transactionId: this.recordId, notes: this.notes })
            .then(() => {
                this.processRefundNow();
                this.closeModal();
            })
            .catch(error => {
                this.showToast('Error Saving Notes', error?.body?.message || 'Unknown error', 'error');
            });
    }

    processRefundNow() {
        processRefund({ transactionId: this.recordId })
            .then(result => {
                const lower = result.toLowerCase();
                if (lower.startsWith('success')) {
                    this.showToast('Refund Successful', result, 'success');
                } else if (lower.includes('already refunded')) {
                    this.showToast('Refund Not Allowed', result, 'warning');
                } else {
                    this.showToast('Refund Failed', result, 'error');
                }
            })
            .catch(error => {
                this.showToast('Refund Error', error?.body?.message || 'Unknown error', 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}