import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getVoidInitData from '@salesforce/apex/DocFlowPackageVoidController.getVoidInitData';
import voidPackage from '@salesforce/apex/DocFlowPackageVoidController.voidPackage';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class DocFlowPackageVoidAction extends LightningElement {
    @api recordId;
    pageRef;
    hasInitialized = false;

    isLoading = true;
    isWorking = false;

    docName = '';
    documentRuntimeId = '';
    packageName = '';
    packageRuntimeId = '';
    packageBlueprintId = '';
    documentStatus = '';
    primaryAccessLink = '';
    sourceRecordId = '';
    alreadyVoided = false;

    voidReason = '';

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        this.pageRef = currentPageReference;
        this.tryInitialize();
    }

    renderedCallback() {
        this.tryInitialize();
    }
    get sourceName() {
    return this.packageName || this.docName || '';
}

get sourceRuntimeId() {
    return this.packageRuntimeId || '';
}

get sourceBlueprintId() {
    return this.packageBlueprintId || '';
}

get showSourceRuntimeId() {
    return !!this.sourceRuntimeId;
}

get showSourceBlueprintId() {
    return !!this.sourceBlueprintId;
}

    get resolvedRecordId() {
        if (this.recordId) {
            return this.recordId;
        }

        if (this.pageRef?.attributes?.recordId) {
            return this.pageRef.attributes.recordId;
        }

        const match = window.location.pathname.match(/\/Doc_Flow_Document__c\/([a-zA-Z0-9]{15,18})\//);
        return match && match[1] ? match[1] : null;
    }

    get disableVoidButton() {
        return this.isWorking || this.isLoading || this.alreadyVoided || !this.documentRuntimeId;
    }

    get statusLabel() {
        return this.documentStatus || 'Unknown';
    }

    async tryInitialize() {
        if (this.hasInitialized) {
            return;
        }

        const docId = this.resolvedRecordId;
        if (!docId) {
            return;
        }

        this.hasInitialized = true;
        await this.loadData(docId);
    }

    async loadData(docId) {
        this.isLoading = true;

        try {
            const response = await getVoidInitData({ docFlowDocumentId: docId });

            this.docName = response.docFlowDocumentName || '';
            this.documentRuntimeId = response.documentRuntimeId || '';
            this.packageName = response.packageName || '';
            this.packageRuntimeId = response.packageRuntimeId || '';
            this.packageBlueprintId = response.packageBlueprintId || '';
            this.documentStatus = response.documentStatus || '';
            this.primaryAccessLink = response.primaryAccessLink || '';
            this.sourceRecordId = response.sourceRecordId || '';
            this.alreadyVoided = !!response.alreadyVoided;
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleReasonChange(event) {
        this.voidReason = event.target.value;
    }

    async handleVoidPackage() {
        this.isWorking = true;

        try {
            const response = await voidPackage({
                docFlowDocumentId: this.resolvedRecordId,
                reason: this.trimValue(this.voidReason)
            });

            this.showToast(
                response.alreadyVoided ? 'Already Voided' : 'Success',
                response.message || 'Document void completed.',
                'success'
            );

            setTimeout(() => {
                this.dispatchEvent(new CloseActionScreenEvent());
            }, 900);
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isWorking = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    trimValue(value) {
        return value ? value.trim() : '';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'Unknown error occurred.';
    }
}