import { LightningElement, track } from 'lwc';
import validateMemberToken  from '@salesforce/apex/MemberAccessApprovalController.validateMemberToken';
import processMemberAction  from '@salesforce/apex/MemberAccessApprovalController.processMemberAction';

const STATE = {
    LOADING:    'loading',
    INVALID:    'invalid',
    EXPIRED:    'expired',
    ALREADY:    'already',
    READY:      'ready',
    SUBMITTING: 'submitting',
    SUCCESS:    'success'
};

export default class MemberAccessApproval extends LightningElement {
    @track state            = STATE.LOADING;
    @track errorMessage     = '';
    @track successMessage   = '';

    @track grantingMemberName = '';

    @track verificationCode = '';

    token = '';

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this.token   = (params.get('token') || '').trim();

        if (!this.token) {
            this.state        = STATE.INVALID;
            this.errorMessage = 'This link is missing a token.';
            return;
        }

        validateMemberToken({ token: this.token })
            .then((info) => {
                this.grantingMemberName = info.authorizedFullName
                    || 'A family member';

                if (info.alreadyProcessed) {
                    this.state        = STATE.ALREADY;
                    this.errorMessage = `This request was already ${String(info.status || '').toLowerCase()}.`;
                } else if (info.expired) {
                    this.state        = STATE.EXPIRED;
                    this.errorMessage = 'This request has expired.';
                } else {
                    this.state = STATE.READY;
                }
            })
            .catch((err) => {
                this.state        = STATE.INVALID;
                this.errorMessage = this.extractMessage(err);
            });
    }

    handleCodeChange(event) {
        this.verificationCode = (event.target.value || '').replace(/\D/g, '').slice(0, 6);
    }

    handleAccept() { this.submit('approve'); }
    handleDeny()   { this.submit('reject');  }

    submit(action) {
        if (!this.verificationCode || this.verificationCode.length !== 6) {
            this.errorMessage = 'Please enter the 6-digit verification code.';
            return;
        }
        this.errorMessage = '';
        this.state        = STATE.SUBMITTING;

        processMemberAction({
            token:            this.token,
            action:           action,
            verificationCode: this.verificationCode
        })
            .then((res) => {
                this.state          = STATE.SUCCESS;
                this.successMessage = res && res.message ? res.message : 'Done.';
            })
            .catch((err) => {
                this.state        = STATE.READY;
                this.errorMessage = this.extractMessage(err);
            });
    }

    extractMessage(err) {
        if (!err) return 'Something went wrong. Please try again.';
        if (err.body) {
            if (err.body.message)        return err.body.message;
            if (Array.isArray(err.body)) return err.body.map((e) => e.message).join(', ');
        }
        return err.message || 'Something went wrong. Please try again.';
    }

    get isLoading()    { return this.state === STATE.LOADING;    }
    get isReady()      { return this.state === STATE.READY;      }
    get isSubmitting() { return this.state === STATE.SUBMITTING; }
    get isSuccess()    { return this.state === STATE.SUCCESS;    }
    get isInvalid()    { return this.state === STATE.INVALID;    }
    get isExpired()    { return this.state === STATE.EXPIRED;    }
    get isAlready()    { return this.state === STATE.ALREADY;    }
    get showForm()     { return this.isReady || this.isSubmitting; }
}