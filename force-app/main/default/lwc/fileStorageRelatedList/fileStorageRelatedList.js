// fileStorageRelatedList.js

import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
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
        cellAttributes: { title: { fieldName: 'sourceType' } }
    },
    {
        label: 'Description',
        fieldName: 'description',
        type: 'text',
        sortable: true,
        wrapText: true,
        cellAttributes: { title: { fieldName: 'description' } }
    },
    {
        label: 'Provider',
        fieldName: 'provider',
        type: 'text',
        sortable: true,
        initialWidth: 180,
        cellAttributes: { title: { fieldName: 'provider' } }
    },
    {
        label: 'Date of Service',
        fieldName: 'dateOfService',
        type: 'text',
        sortable: true,
        initialWidth: 140,
        cellAttributes: { title: { fieldName: 'dateOfService' } }
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

    sortBy;
    sortDirection;

    columns = COLUMNS;

    isLoading = true;
    showDeleteModal = false;
    _pendingDeleteIds = [];

    // ─── Lifecycle ────────────────────────────────
    connectedCallback() {
        this.loadRecords();
    }

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

    // ─── Data Load (imperative) ───────────────────
    loadRecords() {
        this.isLoading = true;

        getFileStorageRecords({ recordId: this.recordId })
            .then(data => {
                this.allRecords = data
                    .map(rec => ({
                        ...rec,
                        name: rec.fileName || rec.name,
                        recordUrl: `/lightning/r/fra__File_Storage__c/${rec.id}/view`,
                        iconName: this.getFileIcon(rec.fileType)
                    }))
                    .sort((a, b) => {
                        const ta = Date.parse(a.dateOfService);
                        const tb = Date.parse(b.dateOfService);
                        const aInvalid = Number.isNaN(ta);
                        const bInvalid = Number.isNaN(tb);
                        if (aInvalid && bInvalid) return 0;
                        if (aInvalid) return -1;
                        if (bInvalid) return 1;
                        return tb - ta;
                    });
            })
            .catch(error => {
                this.showToast('Error', this.reduceErrors(error), 'error');
                this.allRecords = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
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

    // ─── Sort ─────────────────────────────────────
    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        // Name column binds to recordUrl for the link, but should sort by name.
        const sortField = fieldName === 'recordUrl' ? 'name' : fieldName;
        const isAscending = sortDirection === 'asc';

        const sorted = [...this.allRecords].sort((a, b) => {
            const rawA = a[sortField];
            const rawB = b[sortField];

            if (typeof rawA === 'boolean' || typeof rawB === 'boolean') {
                const numA = rawA ? 1 : 0;
                const numB = rawB ? 1 : 0;
                return isAscending ? numA - numB : numB - numA;
            }

            const valueA = rawA == null ? '' : rawA.toString().toLowerCase();
            const valueB = rawB == null ? '' : rawB.toString().toLowerCase();
            return isAscending ? valueA.localeCompare(valueB) : valueB.localeCompare(valueA);
        });

        this.allRecords = sorted;
        this.sortBy = fieldName;
        this.sortDirection = sortDirection;
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
                this.showToast('Success', `${idsToDelete.length} record(s) deleted successfully.`, 'success');
                this.selectedRowIds = [];
                this._pendingDeleteIds = [];
                this.loadRecords();
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
    handleRefresh() {
        this.loadRecords();
    }

    // ─── Upload Success ───────────────────────────
    handleUploadSuccess() {
        this.loadRecords();  // simple imperative reload — no cache issues
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