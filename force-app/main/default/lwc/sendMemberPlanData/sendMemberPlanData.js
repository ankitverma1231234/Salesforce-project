import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import sendAllMemberPlansToThirdParty from '@salesforce/apex/MemberPlanController.sendAllMemberPlansToThirdParty';

export default class SendMemberPlanAction extends LightningElement {

    @api recordId; 

    @api invoke() {
        console.log('Send Member Plan Action triggered for Account:', this.recordId);

        sendAllMemberPlansToThirdParty({ accountId: this.recordId })
            .then(result => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: result || 'All Member Plans sent to third party successfully!',
                        variant: 'success'
                    })
                );

                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(error => {
                const message =
                    error?.body?.message ||
                    error?.message ||
                    'Unknown error occurred while sending data';

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: message,
                        variant: 'error',
                        mode: 'sticky'
                    })
                );

                this.dispatchEvent(new CloseActionScreenEvent());
            });
    }
}