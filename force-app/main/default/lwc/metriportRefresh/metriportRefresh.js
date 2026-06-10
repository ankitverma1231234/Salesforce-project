import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import METRIPORT_PATIENT_ID_FIELD from '@salesforce/schema/Account.Metriport_Patient_Id__c';
import startMetriportCaseFlow from '@salesforce/apex/MetriportNetworkQueryService.startMetriportCaseFlow';

export default class MetriportNetworkQuery extends LightningElement {
    @api recordId;
    hasStarted = false;
    isWorking = true;
    statusMessage = 'Requesting latest records from Metriport...';

    @wire(getRecord, { recordId: '$recordId', fields: [METRIPORT_PATIENT_ID_FIELD] })
    wiredRecord({ data, error }) {
        if (data && !this.hasStarted) {
            this.hasStarted = true;
            const patientId = getFieldValue(data, METRIPORT_PATIENT_ID_FIELD);
            this.run(patientId);
        }
        if (error) {
            this.finish('Could not load the account record.', 'error');
        }
    }

    async run(patientId) {
         console.log('run() called');
        try {
            console.log('Calling Apex...');
            await startMetriportCaseFlow({
                accountId: this.recordId,
                metriportPatientId: patientId
            });
            console.log('Apex Success');
            this.finish(
                'Refresh query started.',
                'success'
            );
        } catch (e) {
            this.finish(e?.body?.message || e?.message || 'Something went wrong.', 'error');
        }
    }

    finish(message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: variant === 'success' ? 'Started' : 'Error',
            message,
            variant
        }));
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}