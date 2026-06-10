import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import FILE_URL_FIELD from '@salesforce/schema/fra__File_Storage__c.fra__File_Public_Url__c';

export default class GdrivePreview extends LightningElement {
    @api recordId;

    rawUrl;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: [FILE_URL_FIELD] })
    wiredRecord({ data, error }) {
        if (data) {
            this.rawUrl = getFieldValue(data, FILE_URL_FIELD);
            this.error = undefined;
        } else if (error) {
            this.error = error.body && error.body.message
                ? error.body.message
                : 'Unable to load record';
            this.rawUrl = undefined;
        }
    }

    // Convert any Google Drive share URL into its embeddable /preview form
    get embedUrl() {
        if (!this.rawUrl) return null;

        // Drive file: /file/d/{ID}/view... -> /preview
        let match = this.rawUrl.match(/\/file\/d\/([a-zA-Z0-9_-]+)/);
        if (match) {
            return `https://drive.google.com/file/d/${match[1]}/preview`;
        }

        // Google Docs
        match = this.rawUrl.match(/\/document\/d\/([a-zA-Z0-9_-]+)/);
        if (match) {
            return `https://docs.google.com/document/d/${match[1]}/preview`;
        }

        // Google Sheets
        match = this.rawUrl.match(/\/spreadsheets\/d\/([a-zA-Z0-9_-]+)/);
        if (match) {
            return `https://docs.google.com/spreadsheets/d/${match[1]}/preview`;
        }

        // Google Slides
        match = this.rawUrl.match(/\/presentation\/d\/([a-zA-Z0-9_-]+)/);
        if (match) {
            return `https://docs.google.com/presentation/d/${match[1]}/preview`;
        }

        // Drive folder
        match = this.rawUrl.match(/\/folders\/([a-zA-Z0-9_-]+)/);
        if (match) {
            return `https://drive.google.com/embeddedfolderview?id=${match[1]}#grid`;
        }

        // Fallback — use the URL as-is
        return this.rawUrl;
    }

    get hasUrl() {
        return !!this.embedUrl;
    }

    get hasError() {
        return !!this.error;
    }

    get showEmptyMessage() {
        return !this.hasUrl && !this.hasError;
    }

    openInDrive() {
        if (this.rawUrl) {
            window.open(this.rawUrl, '_blank');
        }
    }
}