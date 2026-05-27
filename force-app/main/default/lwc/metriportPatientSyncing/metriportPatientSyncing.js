import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import syncAccount from '@salesforce/apex/SyncController.syncAccount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

const FIELDS = ['Account.Metriport_Patient_Id__c'];

export default class AccountMetriportSync extends LightningElement {
    @api recordId;
    patientId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount({ error, data }) {
        if (data) {
            this.patientId = data.fields.Metriport_Patient_Id__c.value;
            this.handleSync();
        } else if (error) {
            this.showToast('Error', 'Unable to load Account', 'error');
            this.closeAction();
        }
    }

    handleSync() {
        syncAccount({ patientId: this.patientId })
            .then(() => {
                this.showToast(
                    'Success',
                    'Patient Syncing Initiated',
                    'success'
                );
                this.closeAction();
            })
            .catch(error => {
                this.showToast(
                    'Error',
                    error.body?.message || 'Sync failed',
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