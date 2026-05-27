import { LightningElement } from 'lwc';
import createPaymentLink from '@salesforce/apex/PaymentLinkController.createPaymentLink';

export default class PaymentLinkGenerator extends LightningElement {
    loading = true;
    errorMessage = '';

    connectedCallback() {
        const urlParams = new URLSearchParams(window.location.search);
        const type = urlParams.get('type');
        const amount = urlParams.get('amount');

        if (!type || !amount) {
            this.errorMessage = 'Invalid payment link. Missing parameters.';
            this.loading = false;
            return;
        }

        createPaymentLink({ typeParam: type, amountParam: parseFloat(amount) })
            .then((redirectUrl) => {
                if (redirectUrl) {
                    window.location.href = redirectUrl;
                } else {
                    this.errorMessage = 'Error: No redirect URL returned.';
                    this.loading = false;
                }
            })
            .catch((error) => {
                this.errorMessage = error.body ? error.body.message : 'Unknown error occurred';
                this.loading = false;
            });
    }
}