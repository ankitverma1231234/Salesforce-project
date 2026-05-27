import { LightningElement, api } from 'lwc';
import sendCaseFiles from '@salesforce/apex/CaseMetriportController.sendCaseFiles';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class CaseMetriportButton extends LightningElement {

    _recordId;
    hasCalled = false;

    @api
    set recordId(value) {
        this._recordId = value;

        if (value && !this.hasCalled) {
            this.hasCalled = true;
            this.uploadFiles();
        }
    }

    get recordId() {
        return this._recordId;
    }

    uploadFiles() {
        sendCaseFiles({ caseId: this._recordId })
            .then(result => {
                this.showToast('Success', result, 'success');
                this.closeAction();
            })
            .catch(error => {
                let message = 'Unexpected error';

                if (error.body && error.body.message) {
                    message = error.body.message;
                }

                this.showToast('Error', message, 'error');
                this.closeAction();
            });
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