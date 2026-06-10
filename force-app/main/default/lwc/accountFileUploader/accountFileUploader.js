import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import confirmUpload from '@salesforce/apex/AccountFileUploaderController.confirmUpload';

const DEFAULT_ACCEPTED_FORMATS = [
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.csv', '.ppt', '.pptx',
    '.txt', '.rtf', '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.svg',
    '.mp4', '.avi', '.mov', '.mp3', '.wav', '.zip', '.rar', '.xml', '.html'
];

export default class AccountFileUploader extends LightningElement {

    @api recordId;
    @api buttonLabel;
    @api iconName = 'utility:upload';
    @api iconPosition = 'left';
    @api iconSize = 'medium';
    @api variant = 'brand';
    @api iconOnly = false;
    @api allowMultiple = false;
    @api modalTitle = 'Upload File';
    @api helpText = 'Select one or more files from your device. Uploaded files will be linked to this Account.';
    @api accept;

    @track showUploadModal = false;
    @track isUploading = false;

    get effectiveButtonLabel() {
        return this.buttonLabel && this.buttonLabel.trim().length > 0
            ? this.buttonLabel
            : 'Upload File';
    }

    get isButtonDisabled() {
        return !this.recordId;
    }

    get acceptedFormatList() {
        if (Array.isArray(this.accept) && this.accept.length > 0) {
            return this.accept;
        }
        if (typeof this.accept === 'string' && this.accept.trim().length > 0) {
            return this.accept
                .split(',')
                .map(ext => ext.trim())
                .filter(ext => ext.length > 0);
        }
        return DEFAULT_ACCEPTED_FORMATS;
    }

    handleOpenUpload() {
        if (!this.recordId) {
            this._toast('Missing Account', 'No Account record is available for upload.', 'warning');
            return;
        }
        this.showUploadModal = true;
    }

    handleCloseUpload() {
        if (this.isUploading) {
            return;
        }
        this.showUploadModal = false;
    }

    handleUploadFinished(event) {
        const uploadedFiles = event?.detail?.files || [];
        if (uploadedFiles.length === 0) {
            this._toast('No File Uploaded', 'No files were uploaded.', 'warning');
            return;
        }

        const documentIds = [...new Set(uploadedFiles
            .map(f => f.documentId)
            .filter(id => !!id))];

        if (documentIds.length === 0) {
            this._toast('Upload Error', 'Uploaded file document ids were not returned.', 'error');
            return;
        }

        this.isUploading = true;

        confirmUpload({ accountId: this.recordId, contentDocumentIds: documentIds })
            .then(result => {
                const fileCount    = uploadedFiles.length;
                const logsCreated  = result?.logsCreated  || 0;
                const logsSkipped  = result?.logsSkipped  || 0;

                let message = `${fileCount} file(s) uploaded and linked successfully.`;
                if (logsCreated > 0) {
                    message += ` ${logsCreated} processing log(s) created.`;
                }
                if (logsSkipped > 0) {
                    message += ` ${logsSkipped} existing log(s) reused.`;
                }

                this._toast('Success', message, 'success');

                this.dispatchEvent(new CustomEvent('uploadsuccess', {
                    detail: {
                        accountId: this.recordId,
                        files: uploadedFiles,
                        confirmation: result
                    },
                    bubbles: true,
                    composed: true
                }));

                this.showUploadModal = false;
            })
            .catch(error => {
                const message = this._reduceError(error);
                const isLogFailure = typeof message === 'string'
                    && message.toLowerCase().includes('processing log');

                this._toast(
                    isLogFailure ? 'Upload Succeeded, Log Failed' : 'Upload Error',
                    message,
                    'error'
                );

                this.dispatchEvent(new CustomEvent('uploaderror', {
                    detail: {
                        error,
                        files: uploadedFiles,
                        partialSuccess: isLogFailure
                    },
                    bubbles: true,
                    composed: true
                }));
            })
            .finally(() => {
                this.isUploading = false;
            });
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _reduceError(error) {
        if (!error) return 'Unknown error';
        if (typeof error === 'string') return error;
        if (Array.isArray(error?.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        if (error.body) {
            if (typeof error.body.message === 'string') return error.body.message;
            if (typeof error.body === 'string') return error.body;
        }
        return error.message || JSON.stringify(error);
    }
}