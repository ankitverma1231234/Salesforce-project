import { LightningElement, api } from 'lwc';
import sendOnboardingLink from '@salesforce/apex/AccountOnboardingNotificationController.sendOnboardingLink';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class OnboardingURLSend extends LightningElement {

    @api recordId;

    @api invoke() {
        sendOnboardingLink({ accountId: this.recordId })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Success',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error?.body?.message || 'Something went wrong',
                        variant: 'error'
                    })
                );
            });
    }
}