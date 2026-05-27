import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getCases from '@salesforce/apex/CaseController.getCases';

export default class CasesTimeline extends NavigationMixin(LightningElement) {
    @api recordId; // Account Id (because component is on Account record page)
    cases;

    @wire(getCases, { accountId: '$recordId' })
    wiredCases({ data, error }) {
        if (data) {
            this.cases = data;
        } else if (error) {
            console.error(error);
        }
    }

    handleCaseClick(event) {
        const caseId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: caseId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }
}