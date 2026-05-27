import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import sendDocument from '@salesforce/apex/DocFlowSendDocumentController.sendDocument';

export default class SendNdaQuickAction extends LightningElement {
    @api recordId;
    isLoading = false;

    async handleSend() {
        this.isLoading = true;

        try {
            const result = await sendDocument({ recordId: this.recordId });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: result.message,
                    variant: 'success'
                })
            );

            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            const message =
                error?.body?.message ||
                error?.message ||
                'Document initiation failed. Please review the recipient details or DocFlow configuration.';

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }
}