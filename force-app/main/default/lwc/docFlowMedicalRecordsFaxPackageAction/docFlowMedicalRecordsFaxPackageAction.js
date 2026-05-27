import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import createDocFlowDocument from '@salesforce/apex/DocFlowQuickActionController.createDocFlowDocument';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

const TEMPLATE_ID = 'be1539b8-d383-4836-8f92-eafa4e0f33bc';

export default class DocFlowMedicalRecordsFaxPackageAction extends LightningElement {
    @api recordId;
    pageRef;
    hasExecuted = false;

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        this.pageRef = currentPageReference;
        this.tryInitialize();
    }

    renderedCallback() {
        this.tryInitialize();
    }

    get resolvedRecordId() {
        if (this.recordId) {
            return this.recordId;
        }

        if (this.pageRef && this.pageRef.attributes && this.pageRef.attributes.recordId) {
            return this.pageRef.attributes.recordId;
        }

        const match = window.location.pathname.match(/\/Account\/([a-zA-Z0-9]{15,18})\//);
        if (match && match[1]) {
            return match[1];
        }

        return null;
    }

    async tryInitialize() {
        if (this.hasExecuted) {
            return;
        }

        const accountId = this.resolvedRecordId;
        if (!accountId) {
            return;
        }

        this.hasExecuted = true;

        try {
            await createDocFlowDocument({
                accountId: accountId,
                templateId: TEMPLATE_ID
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'DocFlow send request initiated.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Please contact your DocFlow support',
                    message: this.reduceError(error),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            setTimeout(() => {
                this.dispatchEvent(new CloseActionScreenEvent());
            }, 500);
        }
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'Unknown error occurred.';
    }
}