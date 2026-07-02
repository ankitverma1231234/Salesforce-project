import { LightningElement, api, track, wire } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getStoredFiles from '@salesforce/apex/AccountStoredFilesViewController.getStoredFiles';
import deleteStoredFile from '@salesforce/apex/AccountStoredFilesViewController.deleteStoredFile';
import deleteStoredFiles from '@salesforce/apex/AccountStoredFilesViewController.deleteStoredFiles';
import updateSendToPortal from '@salesforce/apex/AccountStoredFilesViewController.updateSendToPortal';

export default class AccountStoredFilesView extends NavigationMixin(LightningElement) {
    @api recordId;
    @track isLoading = true;

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        const stateRecordId = pageRef?.state?.c__recordId;
        if (stateRecordId && stateRecordId !== this.recordId) {
            this.recordId = stateRecordId;
        }
    }

    @track fileList = [];
    @track paginatedFileList = [];
    @track currentPage = 1;
    @track pageSize = 20;
    @track totalPages = 1;
    @track sortDirection = 'asc';
    @track sortedBy = 'name';
    @track showSearch = false;
    @track searchKey = '';
    @track searchDate = '';
    @track showAiFiles = false;

    
    @track selectedSourceType = '';
    @track selectedCategory = '';

    @track selectedFileIds = [];
    @track showDeleteModal = false;
    @track pendingDeleteIds = [];
    expandedIds = new Set();
    aiToggleStorageKey = 'accountStoredFilesView.showAiFiles';

    sourceTypeOptions = [
        { label: 'All Source Types', value: '' },
        { label: 'Metriport', value: 'Metriport' },
        { label: 'Health Records', value: 'Health Records' },
        { label: 'AI', value: 'AI' },
        { label: 'Personal Documents', value: 'Personal Documents' }
    ];

    categoryOptions = [
        { label: 'All Categories', value: '' },
        { label: 'Estate, Legal & Financial Documents', value: 'Estate, Legal & Financial Documents' },
        { label: 'Miscellaneous Documents', value: 'Miscellaneous Documents' },
        { label: 'Healthcare Documents', value: 'Healthcare Documents' },
        { label: 'Lab', value: 'Lab' },
        { label: 'Medical Records', value: 'Medical Records' },
        { label: 'Radiology', value: 'Radiology' }
    ];

    connectedCallback() {
        try {
            const stored = sessionStorage.getItem(this.aiToggleStorageKey);
            if (stored === 'true') {
                this.showAiFiles = true;
            }
        } catch (e) {
            
        }
    }

    wiredFileList;

    get sortIcon() {
        return this.sortDirection === 'asc' ? 'utility:arrowup' : 'utility:arrowdown';
    }

    get totalFiles() {
        return this.fileList.filter(file => !file.isAiChild).length;
    }

    get computedTitle() {
        return this.totalFiles === 0 ? 'Files' : `Files (${this.totalFiles})`;
    }

    get isPreviousDisabled() {
        return this.currentPage <= 1;
    }

    get isNextDisabled() {
        return this.currentPage >= this.totalPages;
    }

    get aiToggleLabel() {
        return this.showAiFiles ? 'Hide AI Files' : 'Show AI Files';
    }

    get aiToggleIcon() {
        return this.showAiFiles ? 'utility:hide' : 'utility:preview';
    }

    get aiToggleVariant() {
        return this.showAiFiles ? 'brand' : 'neutral';
    }

    get isDeleteDisabled() {
        return this.selectedFileIds.length === 0;
    }

    get selectedCount() {
        return this.pendingDeleteIds.length;
    }

    @wire(getStoredFiles, { recordId: '$recordId' })
    wiredFiles(result) {
        this.wiredFileList = result;
        this.isLoading = false;

        if (result.data) {
            this.fileList = result.data.map((file, index) => {
                const sourceType = file.sourceType || 'N/A';
                const relatedSummaryFile = file.relatedSummaryFile || null;
                const isAiChild = !!relatedSummaryFile && (sourceType || '').toUpperCase() === 'AI';
                return {
                    id: file.id,
                    key: file.id || `${file.name}_${index}`,
                    name: file.fileName || file.name || 'Untitled File',
                    viewUrl: file.viewUrl,
                    fileUrl: file.fileUrl,
                    recordUrl: file.id ? `/lightning/r/fra__File_Storage__c/${file.id}/view` : null,
                    fileId: file.fileId,
                    lastModifiedDate: file.lastModifiedDate,
                    sendToPortal: file.sendToPortal === true,
                    serviceDateDisplay: this.stripTime(file.serviceDateDisplay) || 'N/A',
                    sourceType,
                    description: file.description || 'N/A',
                    provider: file.provider || 'N/A',
                    iconName: this.getFileIcon(file.fileType),
                    internalFileId: file.internalFileId || null,
                    relatedSummaryFile,
                    isAiChild,
                    category: file.category || '',
                    documentType: file.documentType || '',
                    isSelected: this.selectedFileIds.includes(file.id)
                };
            });
            this.fileList.sort((a, b) => {
                const ta = Date.parse(a.serviceDateDisplay);
                const tb = Date.parse(b.serviceDateDisplay);
                const aInvalid = Number.isNaN(ta);
                const bInvalid = Number.isNaN(tb);
                if (aInvalid && bInvalid) return 0;
                if (aInvalid) return -1;
                if (bInvalid) return 1;
                return tb - ta;
            });
            this.currentPage = 1;
            this.updatePaginatedFiles();
        } else if (result.error) {
            this.fileList = [];
            this.paginatedFileList = [];
            this.totalPages = 1;
            this.showToast('Error', this.reduceError(result.error), 'error');
        }
    }

    async handleUploadSuccess() {
        this.isLoading = true;
        this.selectedFileIds = [];
        try {
            await refreshApex(this.wiredFileList);
            this.updatePaginatedFiles();
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
        const retryDelays = [4000, 10000, 20000];
        for (const delay of retryDelays) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await new Promise(resolve => setTimeout(resolve, delay));
            try {
                await refreshApex(this.wiredFileList);
                this.updatePaginatedFiles();
            } catch (e) {
                
            }
        }
    }

    async handleRefreshButton() {
        this.isLoading = true;
        this.selectedFileIds = [];
        try {
            await refreshApex(this.wiredFileList);
            this.updatePaginatedFiles();
            this.showToast('Info', 'Refreshing file list...', 'info');
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleFileNameClick(event) {
        event.preventDefault();
        this.openFileStorageRecord(event.currentTarget.dataset.id);
    }

    openDriveFile(fileStorageId) {
        const file = this.fileList.find(item => item.id === fileStorageId);
        const previewUrl = file?.viewUrl;
        if (!previewUrl) {
            this.showToast('Error', 'No preview URL is available for this file.', 'error');
            return;
        }
        window.open(previewUrl, '_blank');
    }

    handleMenuSelect(event) {
        const action = event.detail.value;
        const fileStorageId = event.target.dataset.id;
        if (action === 'view_file') {
            this.openDriveFile(fileStorageId);
        } else if (action === 'edit') {
            this.openFileStorageRecord(fileStorageId);
        } else if (action === 'delete') {
            this.handleDeleteClick(fileStorageId);
        }
    }

    openFileStorageRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'fra__File_Storage__c',
                actionName: 'view'
            }
        });
    }

    async handleDeleteClick(fileStorageId) {
        if (!fileStorageId) {
            this.showToast('Error', 'File record Id was not found.', 'error');
            return;
        }
        const confirmed = await LightningConfirm.open({
            message: 'Are you sure you want to delete this file record?',
            variant: 'header',
            label: 'Confirm Delete',
            theme: 'warning'
        });
        if (!confirmed) return;

        this.isLoading = true;
        try {
            await deleteStoredFile({ fileStorageId });
            this.showToast('Success', 'File deleted successfully.', 'success');
            await refreshApex(this.wiredFileList);
            this.updatePaginatedFiles();
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleFileCheckboxChange(event) {
        const fileId = event.target.dataset.id;
        const isChecked = event.target.checked;
        if (isChecked && !this.selectedFileIds.includes(fileId)) {
            this.selectedFileIds = [...this.selectedFileIds, fileId];
        } else if (!isChecked && this.selectedFileIds.includes(fileId)) {
            this.selectedFileIds = this.selectedFileIds.filter(id => id !== fileId);
        }
        this.refreshSelectionState();
    }

    handleSelectAll(event) {
        const isChecked = event.target.checked;
        const visibleIds = this.visibleFileIds;
        if (isChecked) {
            this.selectedFileIds = [...new Set([...this.selectedFileIds, ...visibleIds])];
        } else {
            this.selectedFileIds = this.selectedFileIds.filter(id => !visibleIds.includes(id));
        }
        this.refreshSelectionState();
    }

    refreshSelectionState() {
        this.paginatedFileList = this.paginatedFileList.map(file => ({
            ...file,
            isSelected: this.selectedFileIds.includes(file.id),
            children: (file.children || []).map(child => ({
                ...child,
                isSelected: this.selectedFileIds.includes(child.id)
            }))
        }));
    }

    get visibleFileIds() {
        const ids = [];
        this.paginatedFileList.forEach(file => {
            ids.push(file.id);
            if (file.isExpanded && file.children) {
                file.children.forEach(child => ids.push(child.id));
            }
        });
        return ids;
    }

    get isAllSelected() {
        const visibleIds = this.visibleFileIds;
        return visibleIds.length > 0 && visibleIds.every(id => this.selectedFileIds.includes(id));
    }

    handleDeleteSelected() {
        if (!this.selectedFileIds.length) {
            this.showToast('Warning', 'Please select at least one file to delete.', 'warning');
            return;
        }
        this.pendingDeleteIds = [...this.selectedFileIds];
        this.showDeleteModal = true;
    }

    handleCloseDeleteModal() {
        this.showDeleteModal = false;
        this.pendingDeleteIds = [];
    }

    async confirmMassDelete() {
        this.showDeleteModal = false;
        this.isLoading = true;
        const idsToDelete = [...this.pendingDeleteIds];
        try {
            await deleteStoredFiles({ fileStorageIds: idsToDelete });
            this.showToast('Success', `${idsToDelete.length} file(s) deleted successfully.`, 'success');
            this.selectedFileIds = [];
            this.pendingDeleteIds = [];
            await refreshApex(this.wiredFileList);
            this.updatePaginatedFiles();
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleSort(event) {
        const fieldName = event.currentTarget.dataset.field;
        const isAscending = this.sortedBy === fieldName ? this.sortDirection === 'asc' : true;
        this.sortedBy = fieldName;
        this.sortDirection = isAscending ? 'desc' : 'asc';

        const compare = (a, b) => {
            let valueA = a[fieldName];
            let valueB = b[fieldName];
            if (fieldName === 'sendToPortal') {
                valueA = a.sendToPortal ? 1 : 0;
                valueB = b.sendToPortal ? 1 : 0;
                return isAscending ? valueA - valueB : valueB - valueA;
            }
            valueA = valueA?.toString().toLowerCase() || '';
            valueB = valueB?.toString().toLowerCase() || '';
            return isAscending ? valueA.localeCompare(valueB) : valueB.localeCompare(valueA);
        };

        const parents = this.fileList.filter(file => !file.isAiChild).sort(compare);
        const children = this.fileList.filter(file => file.isAiChild).sort(compare);
        this.fileList = [...parents, ...children];
        this.updatePaginatedFiles();
    }

    handleToggleExpand(event) {
        event.stopPropagation();
        const parentId = event.currentTarget.dataset.id;
        if (!parentId) return;
        if (this.expandedIds.has(parentId)) {
            this.expandedIds.delete(parentId);
        } else {
            this.expandedIds.add(parentId);
        }
        this.updatePaginatedFiles();
    }

    async handleSendToPortalChange(event) {
        const fileStorageId = event.target.dataset.id;
        const newValue = event.target.checked === true;
        if (!fileStorageId) return;

        const previousList = this.fileList;
        this.fileList = this.fileList.map(file =>
            file.id === fileStorageId ? { ...file, sendToPortal: newValue } : file
        );
        this.updatePaginatedFiles();

        try {
            await updateSendToPortal({ fileStorageId, value: newValue });
        } catch (error) {
            this.fileList = previousList;
            this.updatePaginatedFiles();
            this.showToast('Error', this.reduceError(error), 'error');
        }
    }

    handleToggleAiFiles() {
        this.showAiFiles = !this.showAiFiles;
        try {
            sessionStorage.setItem(this.aiToggleStorageKey, String(this.showAiFiles));
        } catch (e) {
            // sessionStorage unavailable
        }
        this.updatePaginatedFiles();
    }

    handleNameSearch(event) {
        this.searchKey = event.target.value;
        this.currentPage = 1;
        this.updatePaginatedFiles();
    }

    handleDateSearch(event) {
        this.searchDate = event.target.value;
        this.currentPage = 1;
        this.updatePaginatedFiles();
    }

    // Source Type dropdown change
    handleSourceTypeChange(event) {
        this.selectedSourceType = event.detail.value || '';
        this.currentPage = 1;
        this.updatePaginatedFiles();
    }

    // Category dropdown change
    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value || '';
        this.currentPage = 1;
        this.updatePaginatedFiles();
    }

    toggleSearch(event) {
        event.stopPropagation();
        this.showSearch = !this.showSearch;
        if (!this.showSearch) {
            this.searchKey = '';
            this.searchDate = '';
            this.updatePaginatedFiles();
        }
    }

    updatePaginatedFiles() {
        const parents = this.fileList.filter(file => !file.isAiChild);
        const aiChildren = this.fileList.filter(file => file.isAiChild);

        const childrenByParentKey = new Map();
        aiChildren.forEach(child => {
            const parentKey = child.relatedSummaryFile;
            if (!parentKey) return;
            if (!childrenByParentKey.has(parentKey)) {
                childrenByParentKey.set(parentKey, []);
            }
            childrenByParentKey.get(parentKey).push(child);
        });

        const searchKeyLower = this.searchKey ? this.searchKey.toLowerCase() : '';
        const searchDateLower = this.searchDate ? this.searchDate.toLowerCase() : '';
        const sourceTypeFilter = this.selectedSourceType || '';
        const categoryFilter = this.selectedCategory || '';

        const matchesFilters = (file) => {
    
    if (searchKeyLower && !file.name?.toLowerCase().includes(searchKeyLower)) return false;
   
    if (searchDateLower && !file.serviceDateDisplay?.toLowerCase().includes(searchDateLower)) return false;

    if (!sourceTypeFilter && !categoryFilter) return true;


    const matchesSourceType = sourceTypeFilter
        ? file.sourceType === sourceTypeFilter
        : false;

    const matchesCategory = categoryFilter
        ? (file.category === categoryFilter || file.documentType === categoryFilter)
        : false;

    if (sourceTypeFilter && !categoryFilter) return matchesSourceType;
    if (categoryFilter && !sourceTypeFilter) return matchesCategory;
    return matchesSourceType || matchesCategory;
    };

        const filteredParents = parents
            .map(parent => {
                const rawChildren = parent.internalFileId
                    ? (childrenByParentKey.get(parent.internalFileId) || [])
                    : [];

                const parentMatches = matchesFilters(parent);
                const matchedChildren = rawChildren.filter(matchesFilters);
                const includeParent = parentMatches || matchedChildren.length > 0;
                if (!includeParent) return null;

                const visibleChildren = (parentMatches ? rawChildren : matchedChildren).map(child => ({
                    ...child,
                    isSelected: this.selectedFileIds.includes(child.id)
                }));
                const hasChildren = visibleChildren.length > 0;
                const forceExpand = !parentMatches && matchedChildren.length > 0;
                const isExpanded = hasChildren && (this.showAiFiles || forceExpand || this.expandedIds.has(parent.id));

                return {
                    ...parent,
                    isSelected: this.selectedFileIds.includes(parent.id),
                    children: visibleChildren,
                    hasChildren,
                    isExpanded,
                    expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                    rowClass: hasChildren ? 'data-row parent-row has-thread' : 'data-row parent-row'
                };
            })
            .filter(Boolean);

        this.totalPages = Math.max(Math.ceil(filteredParents.length / this.pageSize), 1);
        if (this.currentPage > this.totalPages) {
            this.currentPage = this.totalPages;
        }

        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.paginatedFileList = filteredParents.slice(start, end);
    }

    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.updatePaginatedFiles();
        }
    }

    handlePrevious() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.updatePaginatedFiles();
        }
    }

    stripTime(value) {
        if (!value) return '';
        return value.replace(/[,\s]+\d{1,2}:\d{2}(:\d{2})?\s*(AM|PM|am|pm)?\s*$/, '').trim();
    }

    formatDateTime(isoDateTime) {
        const date = new Date(isoDateTime);
        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: false
        }).format(date);
    }

    getFileIcon(fileType) {
        if (!fileType) return 'doctype:unknown';
        const fileTypeLower = fileType.toLowerCase();
        if (fileTypeLower.includes('pdf')) return 'doctype:pdf';
        if (fileTypeLower.includes('image') || fileTypeLower.includes('png') || fileTypeLower.includes('jpg')) return 'doctype:image';
        if (fileTypeLower.includes('word') || fileTypeLower.includes('doc')) return 'doctype:word';
        if (fileTypeLower.includes('excel') || fileTypeLower.includes('xls')) return 'doctype:excel';
        if (fileTypeLower.includes('powerpoint') || fileTypeLower.includes('ppt')) return 'doctype:ppt';
        if (fileTypeLower.includes('text') || fileTypeLower.includes('txt')) return 'doctype:txt';
        if (fileTypeLower.includes('zip') || fileTypeLower.includes('compressed')) return 'doctype:zip';
        return 'doctype:unknown';
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map(item => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}