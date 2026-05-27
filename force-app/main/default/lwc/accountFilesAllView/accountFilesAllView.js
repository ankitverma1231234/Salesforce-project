import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getAccountFiles from '@salesforce/apex/AccountFilesController.getAccountFiles';
import deleteFiles from '@salesforce/apex/AccountFilesController.deleteFiles';

// ─── File Icon Map (fallback) ──────────────────────────────────────────────────
const FILE_ICON_MAP = {
    pdf:   'doctype:pdf',
    doc:   'doctype:word',
    docx:  'doctype:word',
    xls:   'doctype:excel',
    xlsx:  'doctype:excel',
    csv:   'doctype:csv',
    ppt:   'doctype:ppt',
    pptx:  'doctype:ppt',
    txt:   'doctype:txt',
    rtf:   'doctype:rtf',
    png:   'doctype:image',
    jpg:   'doctype:image',
    jpeg:  'doctype:image',
    gif:   'doctype:image',
    bmp:   'doctype:image',
    svg:   'doctype:image',
    tiff:  'doctype:image',
    tif:   'doctype:image',
    mp4:   'doctype:video',
    avi:   'doctype:video',
    mov:   'doctype:video',
    wmv:   'doctype:video',
    mp3:   'doctype:audio',
    wav:   'doctype:audio',
    zip:   'doctype:zip',
    rar:   'doctype:zip',
    '7z':  'doctype:zip',
    xml:   'doctype:xml',
    html:  'doctype:html',
    js:    'doctype:unknown',
    css:   'doctype:unknown',
    snote: 'doctype:unknown',
    pack:  'doctype:pack'
};

const IMAGE_EXTS = ['png','jpg','jpeg','gif','bmp','tif','tiff','svg'];
const SPREADSHEET_EXTS = ['xls','xlsx','csv'];
const WORD_EXTS = ['doc','docx'];

const CHANNEL = '/event/Account_File_Change__e';

const PAGE_SIZE_OPTIONS = [
    { label: '13', value: 13 },
    { label: '25', value: 25 },
    { label: '50', value: 50 }
];

export default class AccountFilesAllView extends NavigationMixin(LightningElement) {

    @api recordId;

    @track allFiles      = [];
    @track groupedParents = [];
    @track selectedIds   = new Set();
    @track expandedParents = new Set();

    searchTerm = '';
    aiGloballyVisible = false;

    forceExpandFromSearch = new Set();

    isLoading        = false;
    showUploadModal  = false;
    showDeleteModal  = false;
    pendingDeleteIds = [];

    sortedBy        = 'serviceDatetime';
    sortedDirection = 'desc';

    pageSize    = 25;
    currentPage = 1;

    wiredResult   = undefined;
    _subscription = null;

    acceptedFormats = [
        '.pdf','.doc','.docx','.xls','.xlsx','.csv','.ppt','.pptx',
        '.txt','.rtf','.png','.jpg','.jpeg','.gif','.bmp','.svg',
        '.mp4','.avi','.mov','.mp3','.wav','.zip','.rar','.xml','.html'
    ];

    // ─── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this._subscribeToEvents();
    }

    disconnectedCallback() {
        this._unsubscribeFromEvents();
    }

    // ─── AI visibility toggle ──────────────────────────────────────────────────

    get aiToggleLabel() {
        return this.aiGloballyVisible ? 'Hide Ai File' : 'Show Ai File';
    }

    get aiToggleIcon() {
        return this.aiGloballyVisible ? 'utility:hide' : 'utility:preview';
    }

    handleToggleAiVisibility() {
        if (this.aiGloballyVisible) {
            // Collapse every parent — only source rows remain
            this.expandedParents = new Set();
            this.aiGloballyVisible = false;
        } else {
            // Expand every parent that has AI children
            const next = new Set();
            this.groupedParents.forEach(p => {
                if (p.children.length > 0) next.add(p.contentDocumentId);
            });
            this.expandedParents = next;
            this.aiGloballyVisible = true;
        }
    }

    // ─── Platform Events (empApi) ──────────────────────────────────────────────

    _subscribeToEvents() {
        onError(error => {
            console.error('[empApi] Global error:', JSON.stringify(error));
        });

        subscribe(CHANNEL, -1, (event) => {
            this._handlePlatformEvent(event);
        })
        .then(subscription => {
            this._subscription = subscription;
            console.log('[empApi] Subscribed to channel:', CHANNEL);
        })
        .catch(error => {
            console.error('[empApi] Subscribe failed:', JSON.stringify(error));
        });
    }

    _unsubscribeFromEvents() {
        if (this._subscription) {
            unsubscribe(this._subscription, () => {
                console.log('[empApi] Unsubscribed from channel:', CHANNEL);
            });
            this._subscription = null;
        }
    }

    _handlePlatformEvent(event) {
        const payload = event?.data?.payload;
        if (!payload || !this.recordId) return;

        const eventAccountId = (payload.Account_Id__c || '').trim();
        const currentId      = (this.recordId || '').trim();

        const isMatch =
            eventAccountId === currentId ||
            eventAccountId.substring(0, 15) === currentId.substring(0, 15);

        if (isMatch) {
            console.log('[empApi] Matching event received — refreshing data');
            this.refreshData();
        }
    }

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        if (!this.recordId && pageRef?.state?.c__recordId) {
            this.recordId = pageRef.state.c__recordId;
        }
    }

    // ─── Wire: Fetch Files ─────────────────────────────────────────────────────

    @wire(getAccountFiles, { accountId: '$recordId' })
    wiredFiles(result) {
        this.wiredResult = result;

        if (!this.recordId) {
            this.isLoading = false;
            return;
        }

        const { data, error } = result;

        if (data) {
            this.allFiles = data.map(file => {
                const iconCfg = this._getFileIconConfig(file);
                return {
                    ...file,
                    fileUrl:   `/lightning/r/ContentDocument/${file.contentDocumentId}/view`,
                    iconName:  iconCfg.iconName,
                    iconClass: iconCfg.iconClass
                };
            });
            this.applySearchAndSort();
            this.isLoading = false;

        } else if (error) {
            this._showToast('Error', this._reduceErrors(error), 'error');
            this.allFiles      = [];
            this.groupedParents = [];
            this.isLoading     = false;
        }
    }

    // ─── Grouping + Search + Sort ──────────────────────────────────────────────

    applySearchAndSort() {
        const all = [...this.allFiles];

        // 1. Partition
        const sourceFiles = all.filter(f => f.source !== 'AI');
        const aiFiles     = all.filter(f => f.source === 'AI');

        // 2. Index AI children by parent ContentDocumentId
        const childrenByParent = new Map();
        aiFiles.forEach(ai => {
            const key = ai.relatedFile;
            if (!key) return;
            if (!childrenByParent.has(key)) childrenByParent.set(key, []);
            childrenByParent.get(key).push(ai);
        });

        // 3. Attach children; track which AI files were claimed
        const claimedAiIds = new Set();
        let parents = sourceFiles.map(p => {
            const children = (childrenByParent.get(p.contentDocumentId) || [])
                .slice()
                .sort((a, b) => this._compareDates(b.serviceDatetime, a.serviceDatetime));
            children.forEach(c => claimedAiIds.add(c.contentDocumentId));
            return { ...p, children };
        });

        // 4. Orphan AI files (no matching parent) — render as own parents
        const orphans = aiFiles
            .filter(ai => !claimedAiIds.has(ai.contentDocumentId))
            .map(ai => ({ ...ai, children: [] }));
        parents = parents.concat(orphans);

        // 5. Search filter — match parent OR any child; auto-expand if only child matched
        this.forceExpandFromSearch = new Set();
        if (this.searchTerm) {
            const term = this.searchTerm;
            const matchesRow = r =>
                (r.title       && r.title.toLowerCase().includes(term))       ||
                (r.description && r.description.toLowerCase().includes(term)) ||
                (r.provider    && r.provider.toLowerCase().includes(term))    ||
                (r.source      && r.source.toLowerCase().includes(term));

            parents = parents.filter(p => {
                const parentHit = matchesRow(p);
                const childHit  = p.children.some(matchesRow);
                if (childHit && !parentHit) {
                    this.forceExpandFromSearch.add(p.contentDocumentId);
                }
                return parentHit || childHit;
            });
        }

        // 6. Sort parents
        parents = this._sortArray(parents, this.sortedBy, this.sortedDirection);

        this.groupedParents = parents;

        // 7. If global "Show AI" toggle is on, re-expand all parents that have children
        if (this.aiGloballyVisible) {
            const next = new Set();
            this.groupedParents.forEach(p => {
                if (p.children.length > 0) next.add(p.contentDocumentId);
            });
            this.expandedParents = next;
        }

        // 8. Clamp current page if it's now out of range
        const pageCount = Math.max(1, Math.ceil(parents.length / this.pageSize));
        if (this.currentPage > pageCount) this.currentPage = pageCount;
    }

    _compareDates(a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1;
        if (b == null) return -1;
        return new Date(a) - new Date(b);
    }

    _sortArray(data, fieldName, direction) {
        const cloned    = [...data];
        const sortField = fieldName === 'fileUrl' ? 'title' : fieldName;
        const isReverse = direction === 'asc' ? 1 : -1;

        cloned.sort((a, b) => {
            let valA = a[sortField];
            let valB = b[sortField];

            if (valA == null && valB == null) return 0;
            if (valA == null) return -isReverse;
            if (valB == null) return  isReverse;

            if (typeof valA === 'boolean') {
                return valA === valB ? 0 : (valA ? isReverse : -isReverse);
            }

            if (typeof valA === 'string') {
                valA = valA.toLowerCase();
                valB = String(valB).toLowerCase();
            }

            return valA > valB ? isReverse : valA < valB ? -isReverse : 0;
        });

        return cloned;
    }

    // ─── Getters: rendered rows ────────────────────────────────────────────────

    get hasFiles() {
        return this.groupedParents?.length > 0;
    }

    get hasNoRecordId() {
        return !this.recordId;
    }

    get filteredFileCount() {
        return this.groupedParents.reduce((sum, p) => sum + 1 + p.children.length, 0);
    }

    get isDeleteDisabled() {
        return this.selectedIds.size === 0;
    }

    get selectedCount() {
        return this.selectedIds.size;
    }

    get pagedParents() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.groupedParents.slice(start, start + this.pageSize);
    }

    get displayedRows() {
        const rows = [];
        const paged = this.pagedParents;
        paged.forEach(parent => {
            const isExpanded = this.expandedParents.has(parent.contentDocumentId)
                || this.forceExpandFromSearch.has(parent.contentDocumentId);
            const hasChildren = parent.children.length > 0;

            rows.push(this._decorateRow(parent, {
                isChild: false,
                hasChildren,
                isExpanded
            }));

            if (isExpanded) {
                parent.children.forEach(child => {
                    rows.push(this._decorateRow(child, {
                        isChild: true,
                        hasChildren: false,
                        isExpanded: false
                    }));
                });
            }
        });
        return rows;
    }

    _decorateRow(file, opts) {
        const isChild = opts.isChild;
        const portal = this._getPortalBadge(file.sendFileToPortal);
        return {
            ...file,
            rowKey:        (isChild ? 'c-' : 'p-') + file.contentDocumentId,
            rowClass:      isChild ? 'data-row child-row' : 'data-row parent-row',
            isChild,
            hasChildren:   opts.hasChildren,
            isExpanded:    opts.isExpanded,
            chevronIcon:   opts.isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            showAiBadge:   isChild,
            isSelected:    this.selectedIds.has(file.contentDocumentId),
            portalLabel:   portal.label,
            portalClass:   portal.className,
            hasPortal:     !!portal.label
        };
    }

    _getPortalBadge(sendFileToPortal) {
        // sendFileToPortal is currently a Boolean on the wrapper. Map true → MyChart pill,
        // and treat any explicit "Patient Portal" extension via fileType later if needed.
        if (sendFileToPortal === true) {
            return { label: 'Sent', className: 'portal-pill portal-mychart' };
        }
        return { label: null, className: null };
    }

    // ─── Pagination ────────────────────────────────────────────────────────────

    get pageInfo() {
        const totalParents = this.groupedParents.length;
        const totalFiles   = this.filteredFileCount;
        const pageCount    = Math.max(1, Math.ceil(totalParents / this.pageSize));

        const pageStartIdx = (this.currentPage - 1) * this.pageSize;
        const pageEndIdx   = Math.min(pageStartIdx + this.pageSize, totalParents);

        // Count files on the current page (parents on page + their children)
        let onPageCount = 0;
        for (let i = pageStartIdx; i < pageEndIdx; i++) {
            onPageCount += 1 + this.groupedParents[i].children.length;
        }

        // Cumulative file index of the first file on this page
        let filesBeforePage = 0;
        for (let i = 0; i < pageStartIdx; i++) {
            filesBeforePage += 1 + this.groupedParents[i].children.length;
        }

        const start = totalFiles === 0 ? 0 : filesBeforePage + 1;
        const end   = filesBeforePage + onPageCount;

        return {
            start,
            end,
            totalFiles,
            totalParents,
            pageCount,
            isFirstPage: this.currentPage <= 1,
            isLastPage:  this.currentPage >= pageCount
        };
    }

    get pageNumbers() {
        const { pageCount } = this.pageInfo;
        const current = this.currentPage;
        const set = new Set([1, pageCount, current - 1, current, current + 1]);
        const pages = [...set].filter(p => p >= 1 && p <= pageCount).sort((a, b) => a - b);

        const out = [];
        let prev = 0;
        pages.forEach(p => {
            if (prev && p - prev > 1) {
                out.push({ key: `gap-${prev}`, isGap: true });
            }
            out.push({
                key: `p-${p}`,
                isGap: false,
                page: p,
                label: String(p),
                isActive: p === current,
                buttonClass: p === current ? 'page-button page-button_active' : 'page-button'
            });
            prev = p;
        });
        return out;
    }

    get pageSizeOptions() {
        return PAGE_SIZE_OPTIONS;
    }

    get pageSizeValue() {
        return String(this.pageSize);
    }

    handlePageChange(event) {
        const page = parseInt(event.currentTarget.dataset.page, 10);
        if (!Number.isNaN(page) && page >= 1 && page <= this.pageInfo.pageCount) {
            this.currentPage = page;
        }
    }

    handlePrevPage() {
        if (this.currentPage > 1) this.currentPage -= 1;
    }

    handleNextPage() {
        if (this.currentPage < this.pageInfo.pageCount) this.currentPage += 1;
    }

    handlePageSizeChange(event) {
        const size = parseInt(event.detail.value, 10);
        if (!Number.isNaN(size) && size > 0) {
            this.pageSize    = size;
            this.currentPage = 1;
        }
    }

    // ─── Search ────────────────────────────────────────────────────────────────

    handleSearch(event) {
        this.searchTerm = event.target.value?.toLowerCase() || '';
        this.selectedIds = new Set();
        this.currentPage = 1;
        this.applySearchAndSort();
    }

    // ─── Expand/collapse ───────────────────────────────────────────────────────

    handleToggleExpand(event) {
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.expandedParents);
        if (next.has(id)) next.delete(id);
        else next.add(id);
        this.expandedParents = next;
    }

    // ─── Selection ─────────────────────────────────────────────────────────────

    handleRowSelect(event) {
        const id = event.target.dataset.id;
        const next = new Set(this.selectedIds);
        if (event.target.checked) next.add(id);
        else next.delete(id);
        this.selectedIds = next;
    }

    handleSelectAll(event) {
        const next = new Set(this.selectedIds);
        if (event.target.checked) {
            this.pagedParents.forEach(p => next.add(p.contentDocumentId));
        } else {
            this.pagedParents.forEach(p => next.delete(p.contentDocumentId));
        }
        this.selectedIds = next;
    }

    get isAllSelectedOnPage() {
        const paged = this.pagedParents;
        return paged.length > 0 && paged.every(p => this.selectedIds.has(p.contentDocumentId));
    }

    // ─── Sorting (header click) ────────────────────────────────────────────────

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (!field) return;
        if (this.sortedBy === field) {
            this.sortedDirection = this.sortedDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortedBy = field;
            this.sortedDirection = 'asc';
        }
        this.applySearchAndSort();
    }

    get sortIndicatorDate() {
        return this._sortArrow('serviceDatetime');
    }
    get sortIndicatorTitle() {
        return this._sortArrow('title');
    }

    _sortArrow(field) {
        if (this.sortedBy !== field) return '';
        return this.sortedDirection === 'asc' ? '▲' : '▼';
    }

    // ─── Row menu action (Preview / Edit / Delete) ─────────────────────────────

    handleRowMenuAction(event) {
        const actionName = event.detail.value;
        const id = event.currentTarget.dataset.id;
        const row = this._findRowById(id);
        if (!row) return;

        switch (actionName) {
            case 'preview':
                this._previewFile(row);
                break;
            case 'edit':
                this._editFileDetails(row);
                break;
            case 'delete':
                this.pendingDeleteIds = [row.contentDocumentId];
                this.showDeleteModal  = true;
                break;
            default:
                console.warn('[AccountFilesAllView] Unknown row action:', actionName);
        }
    }

    _findRowById(id) {
        for (const parent of this.groupedParents) {
            if (parent.contentDocumentId === id) return parent;
            for (const child of parent.children) {
                if (child.contentDocumentId === id) return child;
            }
        }
        return null;
    }

    _previewFile(row) {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: row.contentDocumentId }
        });
    }

    _editFileDetails(row) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:      row.contentVersionId,
                objectApiName: 'ContentVersion',
                actionName:    'edit'
            }
        });
    }

    // ─── Upload ────────────────────────────────────────────────────────────────

    handleAddFile() {
        this.showUploadModal = true;
    }

    handleCloseUploadModal() {
        this.showUploadModal = false;
    }

    handleUploadFinished(event) {
        const uploadedFiles  = event.detail.files;
        this.showUploadModal = false;

        this._showToast(
            'Success',
            `${uploadedFiles.length} file(s) uploaded successfully.`,
            'success'
        );

        this.refreshData();
    }

    // ─── Delete ────────────────────────────────────────────────────────────────

    handleDeleteSelected() {
        if (this.selectedIds.size === 0) {
            this._showToast('Warning', 'Please select at least one file to delete.', 'warning');
            return;
        }
        this.pendingDeleteIds = [...this.selectedIds];
        this.showDeleteModal  = true;
    }

    handleCloseDeleteModal() {
        this.showDeleteModal = false;
        this.pendingDeleteIds = [];
    }

    confirmDelete() {
        const idsToDelete = [...this.pendingDeleteIds];
        this.showDeleteModal = false;
        this.pendingDeleteIds = [];
        this.isLoading = true;

        deleteFiles({ contentDocumentIds: idsToDelete })
            .then(() => {
                this._showToast(
                    'Success',
                    `${idsToDelete.length} file(s) deleted successfully.`,
                    'success'
                );
                idsToDelete.forEach(id => this.selectedIds.delete(id));
                return this.refreshData();
            })
            .catch(error => {
                this._showToast('Error', this._reduceErrors(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ─── Refresh ───────────────────────────────────────────────────────────────

    refreshData() {
        if (!this.wiredResult) {
            console.warn('[AccountFilesAllView] refreshData called before wire resolved — skipping');
            return Promise.resolve();
        }

        this.isLoading = true;

        return refreshApex(this.wiredResult)
            .then(() => {
                this.applySearchAndSort();
            })
            .catch(err => {
                console.error('[AccountFilesAllView] refreshApex error:', err);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ─── Icon configuration ────────────────────────────────────────────────────

    _getFileIconConfig(file) {
        if (file.source === 'AI') {
            return { iconName: 'utility:einstein', iconClass: 'file-icon icon-ai' };
        }
        const ext = (file.fileExtension || '').toLowerCase();
        if (ext === 'pdf') {
            return { iconName: 'doctype:pdf', iconClass: 'file-icon icon-pdf' };
        }
        if (WORD_EXTS.includes(ext)) {
            return { iconName: 'doctype:word', iconClass: 'file-icon icon-docx' };
        }
        if (SPREADSHEET_EXTS.includes(ext)) {
            return { iconName: 'doctype:excel', iconClass: 'file-icon icon-lab' };
        }
        if (IMAGE_EXTS.includes(ext)) {
            return { iconName: 'doctype:image', iconClass: 'file-icon icon-imaging' };
        }
        return { iconName: this._getFileIcon(ext), iconClass: 'file-icon' };
    }

    _getFileIcon(fileType) {
        return fileType
            ? FILE_ICON_MAP[fileType.toLowerCase()] || 'doctype:unknown'
            : 'doctype:unknown';
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _reduceErrors(error) {
        if (!error)                              return 'Unknown error';
        if (typeof error === 'string')           return error;
        if (error.body) {
            if (typeof error.body.message === 'string') return error.body.message;
            if (typeof error.body === 'string')         return error.body;
        }
        return error.message || JSON.stringify(error);
    }
}