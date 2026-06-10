import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getFileStorageRecords from '@salesforce/apex/FileStorageController.getFileStorageRecords';
import deleteFileStorageRecords from '@salesforce/apex/FileStorageController.deleteFileStorageRecords';

const PREVIEW_LIMIT = 6;

const COLUMNS = [
    {
        label: 'Name',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'name' },
            target: '_blank',
            tooltip: { fieldName: 'name' }
        },
        cellAttributes: {
            iconName: { fieldName: 'iconName' },
            iconPosition: 'left'
        },
        sortable: true,
        wrapText: false
    },
    
    {
        label: 'Send to Portal',
        fieldName: 'sendToPortal',
        type: 'boolean',
        sortable: true,
        initialWidth: 130,
        cellAttributes: { alignment: 'center' }
    },
    {
        label: 'Source Type',
        fieldName: 'sourceType',
        type: 'text',
        sortable: true,
        initialWidth: 140,
        cellAttributes: {
            title: { fieldName: 'sourceType' }
        }
    },
    {
        label: 'View File',
        type: 'button',
        typeAttributes: {
            label: 'View',
            name: 'view_file',
            variant: 'brand-outline',
            iconName: 'utility:preview',
            iconPosition: 'left'
        },
        initialWidth: 100,
        cellAttributes: { alignment: 'center' }
    }
];

export default class FileStorageRelatedList extends NavigationMixin(LightningElement) {

    @api recordId;

    @track allRecords = [];
    @track selectedRowIds = [];

    columns = COLUMNS;

    isLoading = true;
    showDeleteModal = false;
    wiredResult;
    _pendingDeleteIds = [];

    // ─── Getters ─────────────────────────────────
    get hasRecords() {
        return this.allRecords?.length > 0;
    }

    get recordCount() {
        return this.allRecords?.length || 0;
    }

    get previewRecords() {
        return this.allRecords.slice(0, PREVIEW_LIMIT);
    }

    get previewCount() {
        return Math.min(PREVIEW_LIMIT, this.recordCount);
    }

    get isDeleteDisabled() {
        return this.selectedRowIds.length === 0;
    }

    get selectedCount() {
        return this._pendingDeleteIds.length;
    }

    // ─── Wire ─────────────────────────────────────
    @wire(getFileStorageRecords, { recordId: '$recordId' })
    wiredRecords(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.allRecords = data.map(rec => ({
                ...rec,
                recordUrl: `/lightning/r/fra__File_Storage__c/${rec.id}/view`,
                iconName: this.getFileIcon(rec.fileType)
            }));
            this.isLoading = false;
        } else if (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.allRecords = [];
            this.isLoading = false;
        }
    }

    // ─── Row Actions ──────────────────────────────
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'view_file') {
            const url = row.fileUrl;

            if (!url) {
                this.showToast('No File URL', 'This record does not have a File URL.', 'warning');
                return;
            }

            window.open(url, '_blank', 'noopener,noreferrer');
        }
    }

    // ─── Row Selection ────────────────────────────
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedRowIds = selectedRows.map(r => r.id);
    }

    // ─── Delete ───────────────────────────────────
    handleDeleteSelected() {
        if (!this.selectedRowIds.length) {
            this.showToast('Warning', 'Please select at least one record to delete.', 'warning');
            return;
        }

        this._pendingDeleteIds = [...this.selectedRowIds];
        this.showDeleteModal = true;
    }

    handleCloseDeleteModal() {
        this.showDeleteModal = false;
        this._pendingDeleteIds = [];
    }

    confirmDelete() {
        this.showDeleteModal = false;
        this.isLoading = true;

        const idsToDelete = [...this._pendingDeleteIds];

        deleteFileStorageRecords({ recordIds: idsToDelete })
            .then(() => {
                this.showToast(
                    'Success',
                    `${idsToDelete.length} record(s) deleted successfully.`,
                    'success'
                );
                this.selectedRowIds = [];
                this._pendingDeleteIds = [];
                return this.refreshData();
            })
            .catch(error => {
                this.showToast('Error', this.reduceErrors(error), 'error');
                this.isLoading = false;
            });
    }

    // ─── View All Drive Files ─────────────────────
    handleViewAllDriveFiles() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Account_Stored_Files_View' },
            state: { c__recordId: this.recordId }
        });
    }

    // ─── Refresh ──────────────────────────────────
    refreshData() {
        this.isLoading = true;

        return refreshApex(this.wiredResult)
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRefresh() {
        this.refreshData();
    }

    // ─── Upload Success (from c-account-file-uploader) ───
    handleUploadSuccess() {
        this.refreshData();
    }

    // ─── Utilities ────────────────────────────────
    getFileIcon(fileType) {
        if (!fileType) return 'doctype:unknown';

        const type = fileType.toLowerCase();
        if (type.includes('pdf')) return 'doctype:pdf';
        if (type.includes('image') || type.includes('png') || type.includes('jpg') || type.includes('jpeg') || type.includes('gif')) return 'doctype:image';
        if (type.includes('word') || type.includes('doc')) return 'doctype:word';
        if (type.includes('excel') || type.includes('xls') || type.includes('csv')) return 'doctype:excel';
        if (type.includes('powerpoint') || type.includes('ppt')) return 'doctype:ppt';
        if (type.includes('text') || type.includes('txt')) return 'doctype:txt';
        if (type.includes('zip') || type.includes('rar') || type.includes('compressed')) return 'doctype:zip';
        if (type.includes('video') || type.includes('mp4') || type.includes('mov')) return 'doctype:video';
        if (type.includes('audio') || type.includes('mp3') || type.includes('wav')) return 'doctype:audio';
        return 'doctype:unknown';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (!error) return 'Unknown error';
        if (typeof error === 'string') return error;

        if (error.body) {
            if (typeof error.body.message === 'string') return error.body.message;
            if (typeof error.body === 'string') return error.body;
        }

        return error.message || JSON.stringify(error);
    }
}