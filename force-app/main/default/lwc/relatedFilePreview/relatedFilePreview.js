import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRelatedFile from '@salesforce/apex/RelatedFilePreviewController.getRelatedFile';

const PREVIEWABLE_TYPES = new Set([
    'pdf', 'png', 'jpg', 'jpeg', 'gif', 'bmp', 'tiff', 'tif', 'svg',
    'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'csv'
]);

export default class RelatedFilePreview extends NavigationMixin(LightningElement) {
    @api recordId;

    file;
    isLoading = true;
    error;

    @wire(getRelatedFile, { contentDocumentId: '$recordId' })
    wiredFile({ error, data }) {
        this.isLoading = false;
        if (error) {
            this.error = error.body ? error.body.message : 'An error occurred while loading the file.';
            this.file = undefined;
        } else {
            this.file = data || undefined;
            this.error = undefined;
        }
    }

    get hasFile() {
        return !!this.file;
    }

    get isPreviewable() {
        return this.hasFile && PREVIEWABLE_TYPES.has(this.file.fileType);
    }

    get previewUrl() {
        if (!this.hasFile) return '';
        return '/sfc/servlet.shepherd/version/download/' + this.file.contentVersionId;
    }

    get fileTitle() {
        return this.hasFile ? this.file.title : '';
    }

    handleOpenFullPreview() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: this.file.contentDocumentId
            }
        });
    }
}