import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
//import { publish } from 'c/fileUploadEventBus';
import confirmUpload from '@salesforce/apex/AccountFileUploaderController.confirmUpload';

const DEFAULT_ACCEPTED_FORMATS = [
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.csv', '.ppt', '.pptx',
    '.txt', '.rtf', '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.svg',
    '.mp4', '.avi', '.mov', '.mp3', '.wav', '.zip', '.rar', '.xml', '.html'
];

export default class AccountFileUploader extends LightningElement {

    @api recordId;
    @api buttonLabel;
    @api iconName      = 'utility:upload';
    @api iconPosition  = 'left';
    @api variant       = 'brand';
    @api iconOnly      = false;
    @api allowMultiple = false;
    @api modalTitle    = 'Upload File';
    @api helpText      = 'Select one or more files from your device. Uploaded files will be linked to this Account.';
    @api accept;

    @track showUploadModal = false;
    @track isUploading     = false;

    _uploadedDocumentId = null;
    _uploadedFileName   = '';

    
    @track formTitle       = '';
    @track formSourceType  = '';
    @track formCategory    = '';
    @track formServiceDate = '';
    @track formDescription = '';

   
    sourceTypeOptions = [
        { label: 'Select source type...',  value: ''                   },
        { label: 'Metriport',              value: 'Metriport'          },
        { label: 'Health Records',         value: 'Health Records'     },
        { label: 'AI',                     value: 'AI'                 },
        { label: 'Personal Documents',     value: 'Personal Documents' }
    ];

    categoryOptions = [
        { label: 'Select category...',                   value: ''                                     },
        { label: 'Estate, Legal & Financial Documents',  value: 'Estate, Legal & Financial Documents'  },
        { label: 'Miscellaneous Documents',              value: 'Miscellaneous Documents'              },
        { label: 'Healthcare Documents',                 value: 'Healthcare Documents'                 },
        { label: 'Lab',                                  value: 'Lab'                                  },
        { label: 'Medical Records',                      value: 'Medical Records'                      },
        { label: 'Radiology',                            value: 'Radiology'                            }
    ];

    get effectiveButtonLabel() {
        return (this.buttonLabel && this.buttonLabel.trim()) ? this.buttonLabel : 'Upload File';
    }

    get isButtonDisabled() {
        return !this.recordId;
    }

    get acceptedFormatList() {
        if (Array.isArray(this.accept) && this.accept.length > 0) return this.accept;
        if (typeof this.accept === 'string' && this.accept.trim()) {
            return this.accept.split(',').map(e => e.trim()).filter(Boolean);
        }
        return DEFAULT_ACCEPTED_FORMATS;
    }

    get hasUploadedFiles() {
        return !!this._uploadedDocumentId;
    }

    get uploadedFileName() {
        return this._uploadedFileName;
    }

    get isSaveDisabled() {
        return this.isUploading || !this._uploadedDocumentId || !this.formTitle.trim();
    }

    handleOpenUpload() {
        if (!this.recordId) {
            this._toast('Missing Account', 'No Account record is available for upload.', 'warning');
            return;
        }
        this._resetForm();
        this.showUploadModal = true;
    }

    handleCloseUpload() {
        if (this.isUploading) return;
        this.showUploadModal = false;
        this._resetForm();
    }

    handleUploadFinished(event) {
        const files = event?.detail?.files || [];
        if (!files.length) {
            this._toast('No File Uploaded', 'No files were uploaded.', 'warning');
            return;
        }

        const file = files[files.length - 1];
        this._uploadedDocumentId = file.documentId;
        this._uploadedFileName   = file.name;

        if (!this.formTitle) {
            this.formTitle = this._stripExtension(file.name);
        }
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value ?? '';

        if (field) {
            this[field] = value;
        }
    }

    _captureLiveFormValues() {
        const sel = (tag, field) =>
            this.template.querySelector(`${tag}[data-field="${field}"]`);

        const titleEl       = sel('lightning-input',    'formTitle');
        const sourceTypeEl  = sel('lightning-combobox', 'formSourceType');
        const categoryEl    = sel('lightning-combobox', 'formCategory');
        const dateEl        = sel('lightning-input',    'formServiceDate');
        const descriptionEl = sel('lightning-textarea', 'formDescription');

        if (titleEl       && titleEl.value)       this.formTitle       = titleEl.value;
        if (sourceTypeEl  && sourceTypeEl.value)  this.formSourceType  = sourceTypeEl.value;
        if (categoryEl    && categoryEl.value)    this.formCategory    = categoryEl.value;
        if (dateEl        && dateEl.value)        this.formServiceDate = dateEl.value;
        if (descriptionEl && descriptionEl.value) this.formDescription = descriptionEl.value;
    }

    async handleSave() {
        this._captureLiveFormValues();

        if (!this._uploadedDocumentId) {
            this._toast('No File', 'Please choose a file to upload.', 'warning');
            return;
        }
        if (!this.formTitle.trim()) {
            this._toast('Title Required', 'Please enter a title for the file.', 'warning');
            return;
        }

        this.isUploading = true;

        try {
            const uploadMetadata = {
                title:           this.formTitle.trim(),
                sourceType:      this.formSourceType  || '',
                category:        this.formCategory    || '',
                description:     this.formDescription || '',
                serviceDateTime: this.formServiceDate
                    ? new Date(this.formServiceDate + 'T00:00:00').toISOString()
                    : ''
            };

            const result = await confirmUpload({
                accountId:          this.recordId,
                contentDocumentIds: [this._uploadedDocumentId],
                uploadMetadataJson: JSON.stringify(uploadMetadata)
            });

            // ── Success ───────────────────────────────────────────────────────
            let message = 'File saved successfully.';
            if (result?.logsCreated > 0) {
                message += ` ${result.logsCreated} processing log(s) created.`;
            }

            this._toast('Success', message, 'success');
            this._toast(
                'Processing in Progress',
                'Your file will appear in the list within a few moments.',
                'info'
            );


            this.dispatchEvent(new CustomEvent('uploadsuccess', {
                detail: {
                    accountId:    this.recordId,
                    files:        [{ name: this._uploadedFileName }],
                    confirmation: result
                },
                bubbles:  true,
                composed: true
            }));

            this.showUploadModal = false;
            this._resetForm();

        } catch (error) {
            const message      = this._reduceError(error);
            const isLogFailure = typeof message === 'string'
                && message.toLowerCase().includes('processing log');

            this._toast(
                isLogFailure ? 'Upload Succeeded, Log Failed' : 'Save Error',
                message,
                'error'
            );

            this.dispatchEvent(new CustomEvent('uploaderror', {
                detail:   { error, partialSuccess: isLogFailure },
                bubbles:  true,
                composed: true
            }));

        } finally {
            this.isUploading = false;
        }
    }

    
    _resetForm() {
        this._uploadedDocumentId = null;
        this._uploadedFileName   = '';
        this.formTitle           = '';
        this.formSourceType      = '';
        this.formCategory        = '';
        this.formServiceDate     = '';
        this.formDescription     = '';
    }

    _stripExtension(filename) {
        if (!filename) return '';
        const dot = filename.lastIndexOf('.');
        return dot > 0 ? filename.substring(0, dot) : filename;
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _reduceError(error) {
        if (!error)                         return 'Unknown error';
        if (typeof error === 'string')      return error;
        if (Array.isArray(error?.body))     return error.body.map(e => e.message).join(', ');
        if (error.body?.message)            return error.body.message;
        if (typeof error.body === 'string') return error.body;
        return error.message || JSON.stringify(error);
    }
}