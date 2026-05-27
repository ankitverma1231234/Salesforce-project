import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import sendPatientDataMethod from '@salesforce/apex/SyncController.sendPatientData';
import sendInsuranceDataMethod from '@salesforce/apex/SyncController.sendInsuranceData';
import UpdateMemberCheckbox from '@salesforce/apex/SyncController.UpdateMemberCheckbox';
import sendFamilyDataMethod  from '@salesforce/apex/SyncController.sendFamilyData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import Id from '@salesforce/schema/Account.Id';

const ACCOUNT_FIELDS = [
    'Account.PersonContactId',
    'Account.Ready_to_Sent__c',
    'Account.FirstName',
    'Account.LastName',
    'Account.PersonEmail',
    'Account.PersonMobilePhone'
];

export default class AccountMetriportSendData extends LightningElement {
    @api recordId;
    contactId;
    readyToSend = false;

    @wire(getRecord, { recordId: '$recordId', fields: ACCOUNT_FIELDS })
    wiredAccount({ error, data }) {
        if (data) {
            const account = data.fields;

            this.contactId = account.PersonContactId?.value;
            this.readyToSend = account.Ready_to_Sent__c?.value;

            const missingFields = [];

            if (!account.FirstName?.value) missingFields.push('First Name');
            if (!account.LastName?.value) missingFields.push('Last Name');
            if (!account.PersonEmail?.value) missingFields.push('Email');
            if (!account.PersonMobilePhone?.value) missingFields.push('Mobile Phone');

            if (missingFields.length > 0) {
                this.showToast(
                    'Error',
                    'Cannot send patient data. Missing fields: ' + missingFields.join(', '),
                    'error'
                );
                this.closeAction();
                return;
            }

            if (!this.readyToSend) {
                this.showToast(
                    'Error',
                    'Metriport Data are still processing. Please try again in a few moments.',
                    'error'
                );
                this.closeAction();
                return;
            }

            this.sendAllData();
        } 
        else if (error) {
            this.showToast('Error', 'Unable to load Account', 'error');
            this.closeAction();
        }
    }

    sendAllData() {
        const patientPromise = sendPatientDataMethod({ contactId: this.contactId });
        const insurancePromise = sendInsuranceDataMethod({ accountId: this.recordId });
        const familyPromise   = sendFamilyDataMethod({ accountId: this.recordId });

        Promise.allSettled([patientPromise, insurancePromise, familyPromise])
            .then(([patientResult, insuranceResult]) => {
                const patientSuccess = patientResult.status === 'fulfilled';
                const insuranceSuccess = insuranceResult.status === 'fulfilled';

                if (patientSuccess && insuranceSuccess) {
                    this.showToast('Success', 'Patient and insurance data sent successfully.', 'success');
                    this.updateCheckbox();

                } else if (patientSuccess && !insuranceSuccess) {
                    this.showToast('Success', 'Patient data sent successfully. No insurance data found or failed to send.', 'success');
                    this.updateCheckbox();

                } else if (!patientSuccess && insuranceSuccess) {
                    this.showToast('Warning', 'Insurance data sent. Patient data failed to send.', 'warning');

                } else {
                    this.showToast('Error', 'Failed to send patient and insurance data.', 'error');
                }

                this.closeAction();
            });
    }

    updateCheckbox(){
        UpdateMemberCheckbox({ accountId: this.recordId })
        .then(() =>{
            console.log('Send_Member_to_portal__c updated successfully');
        })
       .catch(error => {
                console.error('Failed to update checkbox:', error);
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