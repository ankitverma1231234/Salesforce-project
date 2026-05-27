import { LightningElement, api, wire, track } from 'lwc';
import getPersonAccount from '@salesforce/apex/MemberMessagePortalCase.getPersonAccount';
import createCase from '@salesforce/apex/MemberMessagePortalCase.createCase';
import linkFilesToCase from '@salesforce/apex/MemberMessagePortalCase.linkFilesToCase';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class messagePortalCase extends LightningElement {

    @api recordId;

    @track accountName;
    @track contactName;
    contactId;

    subject = '';
    message = '';

    uploadedFiles = [];
    contentDocumentIds = [];

    isLoading = false;

    @wire(getPersonAccount, { accountId: '$recordId' })
    wiredAccount({ data, error }) {
        if (data) {
            this.accountName = data.Name;
            this.contactName = data.PersonContact?.Name;
            this.contactId = data.PersonContactId;
        } else if (error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }

    handleSubjectChange(event) {
        this.subject = event.target.value;
    }

    handleMessageChange(event) {
        this.message = event.target.value;
    }

    handleUploadFinished(event) {
        event.detail.files.forEach(file => {
            this.uploadedFiles = [
                ...this.uploadedFiles,
                { name: file.name, documentId: file.documentId }
            ];
            this.contentDocumentIds = [
                ...this.contentDocumentIds,
                file.documentId
            ];
        });

        this.showToast('Success', 'Files uploaded successfully', 'success');
    }

    handleCreateCase() {
        if (!this.subject || !this.message) {
            this.showToast('Error', 'Subject and Message are required', 'error');
            return;
        }

        this.isLoading = true;

        createCase({
            subject: this.subject,
            description: this.message,
            accountId: this.recordId,
            contactId: this.contactId
        })
        .then(caseId => {
            if (this.contentDocumentIds.length) {
                return linkFilesToCase({
                    caseId: caseId,
                    documentIds: this.contentDocumentIds
                });
            }
        })
        .then(() => {
            this.showToast('Success', 'Case created successfully', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}