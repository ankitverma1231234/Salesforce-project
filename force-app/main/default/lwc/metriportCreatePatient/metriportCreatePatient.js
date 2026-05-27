import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import createPatient from '@salesforce/apex/SyncController.createPatient';
import syncAccount from '@salesforce/apex/SyncController.syncAccount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

const FIELDS = [
    'Account.FirstName',
    'Account.LastName',
    'Account.Date_of_Birth__pc',
    'Account.PersonEmail',
    'Account.PersonMobilePhone',
    'Account.PersonGenderIdentity',
    'Account.PersonMailingStreet',
    'Account.PersonMailingCity',
    'Account.PersonMailingStateCode',
    'Account.PersonMailingPostalCode',
    'Account.PersonMailingCountry'
];

export default class AccountCreateMetriportPatient extends LightningElement {
    recordId;
    hasRun = false;
    account;

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
            this.validateAndCreate();
        } else if (error) {
            this.showToast('Error', 'Failed to load Account', 'error');
            this.closeAction();
        }
    }

    validateAndCreate() {
        const missingFields = [];

        const f = this.account.fields;

        if (!f.FirstName?.value) missingFields.push('First Name');
        if (!f.LastName?.value) missingFields.push('Last Name');
        if (!f.Date_of_Birth__pc?.value) missingFields.push('Date of Birth');
        if (!f.PersonEmail?.value) missingFields.push('Email');
        if (!f.PersonMobilePhone?.value) missingFields.push('Mobile Phone');
        if (!f.PersonGenderIdentity?.value) missingFields.push('Gender');
        if (!f.PersonMailingStreet?.value) missingFields.push('Mailing Street');
        if (!f.PersonMailingCity?.value) missingFields.push('Mailing City');
        if (!f.PersonMailingStateCode?.value) missingFields.push('Mailing State');
        if (!f.PersonMailingPostalCode?.value) missingFields.push('Postal Code');
        if (!f.PersonMailingCountry?.value) missingFields.push('Country');

        if (missingFields.length > 0) {
            this.showToast(
                'Missing Required Fields',
                'Please fill: ' + missingFields.join(', '),
                'error'
            );
            this.closeAction();
            return;
        }
        const zipCode = f.PersonMailingPostalCode.value;
        if (zipCode && zipCode.length > 5) {
            this.showToast(
                'Invalid Postal Code',
                'Postal Code cannot be more than 5 digits.',
                'error'
            );
            this.closeAction();
            return;
        }

        this.createMetriportPatient();
    }

    createMetriportPatient() {
        createPatient({ accountId: this.recordId })
            .then(() => {

                this.showToast('Success', 'Metriport patient creation started', 'success');
                this.handleSync();
                this.closeAction();
            //                 setTimeout(() => {
            //     this.handleSync();
            // }, 300000);
        })
            // Change Time
            .catch(error => {
                this.showToast(
                    'Error',
                    error.body?.message || 'Failed to create Metriport patient',
                    'error'
                );
                this.closeAction();
            });
    }

    handleSync() {
        syncAccount({ accountId: this.recordId })
            .then(() => {
                console.log('Syncing Initiated : ',);
            })
            .catch(error => {
                console.log('Error Occurred : ',error);
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}