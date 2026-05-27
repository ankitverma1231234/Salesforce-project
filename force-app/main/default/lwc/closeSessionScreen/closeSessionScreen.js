import { LightningElement,api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import closeSession from '@salesforce/apex/CloseSessionController.closeSession';

export default class CloseSessionScreen extends LightningElement {
    @api recordId;
    
    @api invoke() {
        closeSession({ sessionId: this.recordId })
            .then(result => {
                const message = result === 'already_closed'
                    ? 'This session is already closed.'
                    : 'Session closed successfully!';

                const variant = result === 'already_closed' ? 'info' : 'success';

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: result === 'already_closed' ? 'Info' : 'Success',
                        message: message,
                        variant: variant
                    })
                );

                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(error => {
                const message =
                    error?.body?.message ||
                    error?.message ||
                    'Unknown error occurred while closing session';

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