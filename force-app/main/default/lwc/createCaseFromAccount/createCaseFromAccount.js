import { LightningElement, api, wire } from 'lwc';
import getAccount from '@salesforce/apex/CreateCaseFromAccountController.getAccount';
import createCase from '@salesforce/apex/CreateCaseFromAccountController.createCase';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class CreateCaseFromAccount extends NavigationMixin(LightningElement) {

    @api recordId;
    accountName;

    @wire(getAccount, { accountId: '$recordId' })
    wiredAccount({ data, error }) {
        if (data) {
            this.accountName = data.Name;
        } else if (error) {
            this.accountName = 'Unable to fetch account';
        }
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleCreateCase() {
        createCase({ accountId: this.recordId })
            .then(caseId => {

                // Success toast
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Case created successfully',
                        variant: 'success'
                    })
                );

                // Close screen wizard
                this.dispatchEvent(new CloseActionScreenEvent());

                // Navigate to Case record
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: caseId,
                        objectApiName: 'Case',
                        actionName: 'view'
                    }
                });
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