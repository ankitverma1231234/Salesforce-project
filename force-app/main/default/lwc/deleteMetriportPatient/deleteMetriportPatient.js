import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import deletePatient from '@salesforce/apex/SyncController.deletePatient';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

const FIELDS = [
    'Account.Metriport_Patient_Id__c'
];

export default class AccountDeleteMetriportPatient extends LightningElement {

    recordId;
    account;
    hasRun = false;

    @wire(CurrentPageReference)
    getPageRef(pageRef) {

        if (!pageRef || this.hasRun) return;

        this.recordId =
            pageRef.state?.recordId ||
            pageRef.attributes?.recordId;

        if (!this.recordId) {
            this.showToast('Error', 'Account context not found', 'error');
            this.closeAction();
            return;
        }

        this.hasRun = true;
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount({ data, error }) {

        if (data) {
            this.account = data;
            this.validateAndDelete();
        }
        else if (error) {
            this.showToast('Error', 'Failed to load Account', 'error');
            this.closeAction();
        }
    }

    validateAndDelete() {

        const metriportId = this.account.fields.Metriport_Patient_Id__c?.value;

        if (!metriportId) {
            this.showToast(
                'Error',
                'No Metriport Patient Id found on this Account',
                'error'
            );
            this.closeAction();
            return;
        }

        this.deleteMetriportPatient();
    }

    deleteMetriportPatient() {

        deletePatient({ accountId: this.recordId })
            .then(() => {

                this.showToast(
                    'Success',
                    'Metriport patient deletion started',
                    'success'
                );

                this.closeAction();
            })
            .catch(error => {

                this.showToast(
                    'Error',
                    error.body?.message || 'Failed to delete Metriport patient',
                    'error'
                );

                this.closeAction();
            });
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