import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue }    from 'lightning/uiRecordApi';
import { CloseActionScreenEvent }      from 'lightning/actions';
import { ShowToastEvent }              from 'lightning/platformShowToastEvent';
import resendEmail from '@salesforce/apex/ResendApprovalEmailController.resendEmail';

import PORTAL_STATUS_FIELD  from '@salesforce/schema/Account_Head_Relationship__c.Portal_Access_Status__c';
import REQUEST_ACCESS_FIELD from '@salesforce/schema/Account_Head_Relationship__c.Request_Access__c';
import GIVE_ACCESS_FIELD    from '@salesforce/schema/Account_Head_Relationship__c.Give_Access__c';

const FIELDS = [PORTAL_STATUS_FIELD, REQUEST_ACCESS_FIELD, GIVE_ACCESS_FIELD];

export default class ResendApprovalEmail extends LightningElement {
    @api recordId;

    _portalStatus  = '';
    _requestAccess = false;
    _giveAccess    = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this._portalStatus  = getFieldValue(data, PORTAL_STATUS_FIELD)  || '';
            this._requestAccess = getFieldValue(data, REQUEST_ACCESS_FIELD) || false;
            this._giveAccess    = getFieldValue(data, GIVE_ACCESS_FIELD)    || false;
        }
        if (error) {
            this._portalStatus  = '';
            this._requestAccess = false;
            this._giveAccess    = false;
        }
    }

    get _canResend() {
        return this._portalStatus === 'Pending'
            && (this._requestAccess === true || this._giveAccess === true);
    }

    @api invoke() {
        if (!this._canResend) {
            this._showBlockedToast();
            this.dispatchEvent(new CloseActionScreenEvent());
            return;
        }

        resendEmail({ recordId: this.recordId })
            .then(() => {
                this._toast('Email Sent', 'Approval email has been resent successfully.', 'success', 'dismissable');
            })
            .catch((err) => {
                this._toast('Error Sending Email', this._extractMessage(err), 'error', 'sticky');
            })
            .finally(() => {
                this.dispatchEvent(new CloseActionScreenEvent());
            });
    }

    _showBlockedToast() {
        const statusOk   = this._portalStatus === 'Pending';
        const checkboxOk = this._requestAccess || this._giveAccess;

        let message;
        if (!statusOk && !checkboxOk) {
            message = `Status must be "Pending" (current: "${this._portalStatus}") `
                    + `and at least one of Request Access or Give Access must be checked.`;
        } else if (!statusOk) {
            message = `Email can only be resent when status is "Pending". `
                    + `Current status: "${this._portalStatus}".`;
        } else {
            message = 'At least one of "Request Access" or "Give Access" must be checked before resending.';
        }

        this._toast('Cannot Resend', message, 'warning', 'dismissable');
    }

    _toast(title, message, variant, mode) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode }));
    }

    _extractMessage(err) {
        if (!err)              return 'Something went wrong. Please try again.';
        if (err.body?.message) return err.body.message;
        if (Array.isArray(err.body)) return err.body.map(e => e.message).join(', ');
        return err.message     || 'Something went wrong. Please try again.';
    }
}