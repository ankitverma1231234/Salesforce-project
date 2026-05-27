import { LightningElement, api } from 'lwc';
import sendCaseFiles from '@salesforce/apex/CaseMetriportController.sendCaseFiles';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class SendFileToMetriportFromCase extends LightningElement {

    @api recordId;

    @api async invoke() {
        try {
            const result = await sendCaseFiles({ caseId: this.recordId });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: result,
                    variant: 'success'
                })
            );

        } catch (error) {
            let message = 'Unexpected error';

            if (error.body && error.body.message) {
                message = error.body.message;
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: message,
                    variant: 'error'
                })
            );
        }
    }
}