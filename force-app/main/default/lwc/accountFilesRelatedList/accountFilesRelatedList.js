import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

import getAccountFiles from '@salesforce/apex/AccountFilesController.getAccountFiles';
import deleteFiles from '@salesforce/apex/AccountFilesController.deleteFiles';

// File Icon Map
const FILE_ICON_MAP = {
    pdf: 'doctype:pdf',
    doc: 'doctype:word',
    docx: 'doctype:word',
    xls: 'doctype:excel',
    xlsx: 'doctype:excel',
    csv: 'doctype:csv',
    ppt: 'doctype:ppt',
    pptx: 'doctype:ppt',
    txt: 'doctype:txt',
    rtf: 'doctype:rtf',
    png: 'doctype:image',
    jpg: 'doctype:image',
    jpeg: 'doctype:image',
    gif: 'doctype:image',
    bmp: 'doctype:image',
    svg: 'doctype:image',
    tiff: 'doctype:image',
    tif: 'doctype:image',
    mp4: 'doctype:video',
    avi: 'doctype:video',
    mov: 'doctype:video',
    wmv: 'doctype:video',
    mp3: 'doctype:audio',
    wav: 'doctype:audio',
    zip: 'doctype:zip',
    rar: 'doctype:zip',
    '7z': 'doctype:zip',
    xml: 'doctype:xml',
    html: 'doctype:html',
    js: 'doctype:unknown',
    css: 'doctype:unknown',
    snote: 'doctype:unknown',
    pack: 'doctype:pack'
};

const PREVIEW_LIMIT = 6;
const CHANNEL = '/event/Account_File_Change__e';

// Datatable Columns
const COLUMNS = [
    
    {
    label: 'Title',
    fieldName: 'fileUrl',
    type: 'url',
    typeAttributes: {
        label: { fieldName: 'title' },
        target: '_blank',
        tooltip: { fieldName: 'title' } // 👈 THIS IS THE FIX
    },
    cellAttributes: {
        iconName: { fieldName: 'iconName' },
        iconPosition: 'left'
    },
    sortable: true,
    initialWidth: 250,
    wrapText: false
    },
{
    label: 'Description',
    fieldName: 'description',
    type: 'text',
    wrapText: false,
    initialWidth: 200,
    cellAttributes: {
        title: { fieldName: 'description' } // 👈 ADD THIS
    }
},
       
    {
        label: 'Type',
        fieldName: 'fileExtension',
        type: 'text',
        sortable: true,
        initialWidth: 80,
        
        cellAttributes: { alignment: 'left' }
    },
    
    {
        label: 'Date',
        fieldName: 'serviceDatetime',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit'
        },
        sortable: true,
        initialWidth: 130,
        
    },
    {
        label: 'Portal',
        fieldName: 'sendFileToPortal',
        type: 'boolean',
        sortable: false,
        initialWidth: 80,
        
        cellAttributes: { alignment: 'center' }
    },
    {
        label: 'Source',
        fieldName: 'source',
        type: 'text',
        sortable: true,
        initialWidth: 150,
        
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Preview File', name: 'preview' },
                { label: 'Edit File Details', name: 'edit' },
                { label: 'Delete File', name: 'delete' }
            ]
        }
    }
];

export default class AccountFilesRelatedList extends NavigationMixin(LightningElement) {

    @api recordId;

    @track allFiles = [];
    @track selectedRowIds = [];

    columns = COLUMNS;

    isLoading = true;
    showUploadModal = false;
    showDeleteModal = false;

    wiredResult;
    _pendingDeleteIds = [];
    _subscription = null;

    acceptedFormats = [
        '.pdf','.doc','.docx','.xls','.xlsx','.csv','.ppt','.pptx',
        '.txt','.rtf','.png','.jpg','.jpeg','.gif','.bmp','.svg',
        '.mp4','.avi','.mov','.mp3','.wav','.zip','.rar','.xml','.html'
    ];

    // ─── Lifecycle ────────────────────────────────
    connectedCallback() {
        this._subscribeToEvents();
    }

    disconnectedCallback() {
        this._unsubscribeFromEvents();
    }

    // ─── Platform Events ──────────────────────────
    _subscribeToEvents() {
        onError(error => {
            console.error('empApi error:', JSON.stringify(error));
        });

        subscribe(CHANNEL, -1, (event) => {
            this._handlePlatformEvent(event);
        })
        .then(subscription => {
            this._subscription = subscription;
        })
        .catch(error => {
            console.error('empApi subscribe error:', JSON.stringify(error));
        });
    }

    _unsubscribeFromEvents() {
        if (this._subscription) {
            unsubscribe(this._subscription, () => {});
            this._subscription = null;
        }
    }

    _handlePlatformEvent(event) {
        const payload = event.data.payload;

        if (payload.Account_Id__c && payload.Account_Id__c === this.recordId) {
            this.refreshData();
        }
    }

    // ─── Getters ─────────────────────────────────
    get hasFiles() {
        return this.allFiles?.length > 0;
    }

    get fileCount() {
        return this.allFiles?.length || 0;
    }

    get previewFiles() {
        return this.allFiles.slice(0, PREVIEW_LIMIT);
    }

    get previewCount() {
        return Math.min(PREVIEW_LIMIT, this.fileCount);
    }

    get isDeleteDisabled() {
        return this.selectedRowIds.length === 0;
    }

    get selectedCount() {
        return this._pendingDeleteIds.length;
    }

    // ─── Wire ─────────────────────────────────────
    @wire(getAccountFiles, { accountId: '$recordId' })
    wiredFiles(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.allFiles = data.map(file => ({
    ...file,
    iconName: this.getFileIcon(file.fileExtension),

    // 👇 ADD THIS
    fileUrl: `/lightning/r/ContentDocument/${file.contentDocumentId}/view`
}));
            this.isLoading = false;

        } else if (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.allFiles = [];
            this.isLoading = false;
        }
    }

    // ─── Row Selection ────────────────────────────
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedRowIds = selectedRows.map(r => r.contentDocumentId);
    }

    // ─── Row Actions ──────────────────────────────
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        switch (actionName) {
            case 'preview':
                this[NavigationMixin.Navigate]({
                    type: 'standard__namedPage',
                    attributes: { pageName: 'filePreview' },
                    state: { selectedRecordId: row.contentDocumentId }
                });
                break;

            case 'edit':
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: row.contentVersionId,
                        objectApiName: 'ContentVersion',
                        actionName: 'edit'
                    }
                });
                break;

            case 'delete':
                this._pendingDeleteIds = [row.contentDocumentId];
                this.showDeleteModal = true;
                break;
        }
    }

    // ─── Delete ───────────────────────────────────
    handleDeleteSelected() {
        if (!this.selectedRowIds.length) {
            this.showToast('Warning', 'Please select at least one file to delete.', 'warning');
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

        deleteFiles({ contentDocumentIds: idsToDelete })
            .then(() => {
                this.showToast(
                    'Success',
                    `${idsToDelete.length} file(s) deleted successfully.`,
                    'success'
                );
                this.selectedRowIds = [];
                this._pendingDeleteIds = [];
                this.refreshData();
            })
            .catch(error => {
                this.showToast('Error', this.reduceErrors(error), 'error');
                this.isLoading = false;
            });
    }

    // ─── Upload ───────────────────────────────────
    handleAddFile() {
        this.showUploadModal = true;
    }

    handleCloseUploadModal() {
        this.showUploadModal = false;
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        this.showUploadModal = false;

        this.showToast(
            'Success',
            `${uploadedFiles.length} file(s) uploaded successfully.`,
            'success'
        );

        this.refreshData();
    }

    // ─── View All ─────────────────────────────────
    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Account_Files_All_View' },
            state: { c__recordId: this.recordId }
        });
    }

    // ─── Utilities ────────────────────────────────
    getFileIcon(fileType) {
        return fileType
            ? FILE_ICON_MAP[fileType.toLowerCase()] || 'doctype:unknown'
            : 'doctype:unknown';
    }

    refreshData() {
        this.isLoading = true;

        return refreshApex(this.wiredResult)
            .finally(() => {
                this.isLoading = false;
            });
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