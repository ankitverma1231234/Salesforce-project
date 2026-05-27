import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFileInfo from '@salesforce/apex/GeminiFileInsightsController.getFileInfo';
import getAnalysisBundle from '@salesforce/apex/GeminiFileInsightsController.getAnalysisBundle';
import getParentRecordId from '@salesforce/apex/GeminiFileInsightsController.getParentRecordId';
import getPatientContext from '@salesforce/apex/GeminiFileInsightsController.getPatientContext';
import generateFullAnalysis from '@salesforce/apex/GeminiFileInsightsController.generateFullAnalysis';
import generateAndDownloadPdf from '@salesforce/apex/GeminiFileInsightsController.generateAndDownloadPdf';
import getAnalysisStatus from '@salesforce/apex/GeminiFileInsightsController.getAnalysisStatus';
import syncAnalysisPdf from '@salesforce/apex/GeminiFileInsightsController.syncAnalysisPdf';
import askQuestion from '@salesforce/apex/GeminiFileInsightsController.askQuestion';
import getRelatedFile from '@salesforce/apex/RelatedFilePreviewController.getRelatedFile';
import { NavigationMixin } from 'lightning/navigation';


// Tab catalog. Ordering here mirrors the PDF section order so the LWC preview
// stays visually in sync with the generated PDF. Tabs for section keys the AI
// did not return are filtered out of `tabItems` (see getter below) — this is
// the LWC equivalent of the Visualforce `rendered="{!NOT(ISBLANK(...))}"` rule.
const TABS = [
    { id: 'summary', label: 'Summary', dotColor: '#2F6FED' },
    { id: 'keyFindings', label: 'Key Findings', dotColor: '#D92D20' },
    // Extended clinical sections
    { id: 'chiefComplaint', label: 'Chief Complaint', dotColor: '#D92D20' },
    { id: 'keySymptoms', label: 'Key Symptoms', dotColor: '#C76A00' },
    { id: 'allergies', label: 'Allergies', dotColor: '#D92D20' },
    { id: 'currentMedications', label: 'Current Medications', dotColor: '#7A3E9D' },
    { id: 'medicalHistory', label: 'Medical History', dotColor: '#2F6FED' },
    { id: 'surgicalHistory', label: 'Surgical History', dotColor: '#0A7C86' },
    { id: 'familyHistory', label: 'Family History', dotColor: '#0A7C86' },
    { id: 'socialHistory', label: 'Social History', dotColor: '#1E9E5A' },
    { id: 'physicalExam', label: 'Physical Exam', dotColor: '#1E9E5A' },
    { id: 'labs', label: 'Labs', dotColor: '#1E9E5A' },
    { id: 'imaging', label: 'Imaging', dotColor: '#7A3E9D' },
    { id: 'assessment', label: 'Assessment', dotColor: '#2F6FED' },
    { id: 'differentialDiagnoses', label: 'Differential Diagnoses', dotColor: '#C76A00' },
    { id: 'treatmentPlan', label: 'Treatment Plan', dotColor: '#2F6FED' },
    // Legacy keys (kept for backward compatibility with older cached analyses)
    { id: 'medicationReview', label: 'Medication Review', dotColor: '#7A3E9D' },
    { id: 'labVitals', label: 'Lab & Vitals', dotColor: '#1E9E5A' },
    { id: 'riskAssessment', label: 'Risk Assessment', dotColor: '#C76A00' },
    { id: 'actionItems', label: 'Action Items', dotColor: '#2F6FED' },
    { id: 'patientSummary', label: 'Patient Summary', dotColor: '#0A7C86' }
];

// A section counts as "empty" when it's missing, whitespace-only, or only
// contains the placeholder text emitted by the Apex normalizer.
function isSectionBlank(html) {
    if (!html) return true;
    const stripped = String(html).replace(/<[^>]*>/g, '').trim().toLowerCase();
    if (!stripped) return true;
    return stripped === 'no information available for this section.'
        || stripped === 'no information available.'
        || stripped === 'not documented.'
        || stripped === 'n/a'
        || stripped === '-';
}

const GROUP_ICON_MAP = {
    'Patient Demographics': 'standard:contact',
    'Clinical Summary': 'standard:document',
    'Diagnoses & Risks': 'standard:diagnosis',
    'Medications': 'standard:medication',
    'Labs & Vitals': 'standard:scan_card',
    'Insurance & Coverage': 'standard:partners',
    'Social & Lifestyle': 'standard:people',
    'Care Coordination': 'standard:care_request_review',
    'Administrative': 'standard:snippet',
    'Extracted Fields': 'standard:record'
};

const TAG_THEME_CLASSES = [
    'tag-group theme-0',
    'tag-group theme-1',
    'tag-group theme-2',
    'tag-group theme-3',
    'tag-group theme-4',
    'tag-group theme-5'
];

export default class GeminiFileInsights extends NavigationMixin (LightningElement) {
    @api recordId;
      file;

    @track fileInfo;
    @track parentRecordId;
    @track analysis;
    @track activeTab = 'summary';
    @track isLoading = false;
    @track isQuestionLoading = false;
    @track errorMessage;
    @track question = '';
    @track answer;
    @track sourceUpdated = false;
    @track loadedFromSavedNote = false;
    @track isAiGeneratedFile = false;
    @track hasCurrentPdf = false;
    @track isPdfSyncing = false;
    @track isDocumentReady = false;
    @track patientContext;

    _initialized = false;
    _wiredFileResult;

    @wire(getRelatedFile, { contentDocumentId: '$recordId' })
    wiredFile(result) {
        this._wiredFileResult = result;
        const { error, data } = result;
        this.isLoading = false;
        if (error) {
            this.error = error.body ? error.body.message : 'An error occurred while loading the file.';
            this.file = undefined;
        } else {
            this.file = data || undefined;
            this.error = undefined;
        }
    }

    /**
     * Preview priority:
     *   1. Freshly synced AI PDF (always up-to-date after syncPdfDocument)
     *   2. Wire-returned related file (cached, may lag behind)
     *   3. Source file itself (the recordId — always available)
     */
    handleOpenFullPreview() {
        const previewDocId =
            (this.analysis && this.analysis.pdfDocumentId)
            || (this.file && this.file.contentDocumentId)
            || this.recordId;

        if (!previewDocId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: previewDocId
            }
        });
    }
    renderedCallback() {
        if (!this._initialized && this.recordId) {
            this._initialized = true;
            this.initialize();
        }
    }



async initialize() {
    this.isDocumentReady = false;

    try {
        await this.loadFileInfo();
        console.log('check ai generated flag',this.isAiGeneratedFile);
        if (this.isAiGeneratedFile) {
            return;
        }

        await this.loadParentRecordId();
        await this.loadPatientContext();
        const hasAnalysis = await this.loadAnalysis();

        if (!hasAnalysis && !this.isSourceSummaryGenerated) {
            await this.runAnalysis(false, false);
            await this.syncPdfDocument();
        } else if (hasAnalysis && !this.isSourceSummaryGenerated) {
            await this.syncPdfDocument();
        }
    } catch (error) {
        this.errorMessage = this.reduceErrors(error);
    } finally {
        // Always mark ready so the UI is usable even when an error occurred.
        // Preview availability is handled independently by isPreviewUnavailable.
        this.isDocumentReady = true;
    }
}

async loadParentRecordId() {
    this.parentRecordId = await getParentRecordId({ contentDocumentId: this.recordId });
}

async loadPatientContext() {
    try {
        this.patientContext = await getPatientContext({ contentDocumentId: this.recordId });
    } catch (e) {
        // Non-critical — patient card simply won't render
    }
}

    async loadFileInfo() {
        this.fileInfo = await getFileInfo({ contentDocumentId: this.recordId });

        // Treat the file as an AI-generated artifact if its title matches the
        // phrases our generator emits. "ai generated summary" is the current
        // format; "ai summary" is kept for older attachments.
        if (this.fileInfo && this.fileInfo.title) {
            const titleLower = this.fileInfo.title.toLowerCase();
            this.isAiGeneratedFile =
                titleLower.includes('ai generated summary') ||
                titleLower.includes('ai summary');
                
            this.isSourceSummaryGenerated = this.fileInfo.isAiSummaryGenerated === 'true';
        }
    }

    async loadAnalysis() {
        const result = await getAnalysisBundle({ contentDocumentId: this.recordId });
        if (!result) {
            return false;
        }
        this.hydrateAnalysis(result);

        // Check status for staleness and source
        try {
            const status = await getAnalysisStatus({ contentDocumentId: this.recordId });
            this.sourceUpdated = status.isStale === true;
            this.loadedFromSavedNote = status.hasStoredNote === true;
            this.hasCurrentPdf = status.hasPdf === true;
        } catch (e) {
            // Non-critical, continue
        }

        return true;
    }

   hydrateAnalysis(rawPayload) {
    let parsed;
    
    if (typeof rawPayload === 'string') {
        try {
            parsed = JSON.parse(rawPayload);
        } catch (e) {
            // If double-encoded, try parsing twice
            try {
                parsed = JSON.parse(JSON.parse(rawPayload));
            } catch (e2) {
                parsed = {};
            }
        }
    } else {
        parsed = rawPayload;
    }

    parsed.sections = parsed.sections || {};
    parsed.tagGroups = Array.isArray(parsed.tagGroups) ? parsed.tagGroups : [];
    parsed.keyFields = Array.isArray(parsed.keyFields) ? parsed.keyFields : [];

    this.analysis = parsed;

    if (parsed.pdfVersionId || parsed.analysisVersionId) {
        this.hasCurrentPdf = true;
    }

    // If the current tab has no content (e.g. a legacy 'summary' default when
    // the AI only emitted clinical sections), jump to the first tab that does.
    if (isSectionBlank(parsed.sections[this.activeTab])) {
        const firstVisible = TABS.find(tab => !isSectionBlank(parsed.sections[tab.id]));
        this.activeTab = firstVisible ? firstVisible.id : 'summary';
    }
}

    async runAnalysis(forceRegenerate, showToast) {
    this.isLoading = true;
    this.errorMessage = null;

    try {
        const result = await generateFullAnalysis({
            contentDocumentId: this.recordId,
            forceRegenerate: forceRegenerate,
            attachPdf: false
        });

        this.hydrateAnalysis(result);
        this.sourceUpdated = false;
        this.loadedFromSavedNote = false;

        if (showToast) {
            this.showToast(
                'Success',
                forceRegenerate
                    ? 'AI analysis refreshed and saved.'
                    : 'AI analysis generated and saved.',
                'success'
            );
        }
    } catch (error) {
        this.errorMessage = this.reduceErrors(error);
        if (showToast) {
            this.showToast('Error', this.errorMessage, 'error');
        }
    } finally {
        this.isLoading = false;
    }
}

    handleTabClick(event) {
        const tabId = event.currentTarget.dataset.id;
        if (tabId) {
            this.activeTab = tabId;
        }
    }

    async handleRegenerateAnalysis() {
        this.isDocumentReady = false;
        this.errorMessage = null;

        try {
            await this.runAnalysis(true, false);
            await this.syncPdfDocument();
            this.showToast('Success', 'AI analysis and PDF refreshed.', 'success');
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            // Always restore so the UI remains usable even after errors
            this.isDocumentReady = true;
        }
    }

    async syncPdfDocument() {
        this.isPdfSyncing = true;
        try {
            const result = await syncAnalysisPdf({
                contentDocumentId: this.recordId
            });
            if (result && this.analysis) {
                this.analysis = {
                    ...this.analysis,
                    analysisVersionId: result.contentVersionId,
                    pdfVersionId: result.contentVersionId,
                    pdfDocumentId: result.contentDocumentId
                };
            }
            this.hasCurrentPdf = true;

            // Refresh the wire so this.file picks up the newly created/updated AI PDF
            if (this._wiredFileResult) {
                await refreshApex(this._wiredFileResult);
            }
        } finally {
            this.isPdfSyncing = false;
        }
    }

    async handleOpenAnalysisPdf() {
        if (this.isBusy || !this.analysisReady) {
            return;
        }

        this.errorMessage = null;

        try {
            await this.syncPdfDocument();

            if (this.analysis && this.analysis.pdfVersionId) {
                window.open(`/sfc/servlet.shepherd/version/download/${this.analysis.pdfVersionId}`, '_blank');
            }

            this.showToast('Success', 'AI PDF generated and attached to the record.', 'success');
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
            this.showToast('Error', this.errorMessage, 'error');
        }
    }

    handleQuestionChange(event) {
        this.question = event.target.value;
    }

    handleKeyUp(event) {
        if (event.key === 'Enter' && !this.isAskDisabled) {
            this.handleAskQuestion();
        }
    }

    async handleAskQuestion() {
        if (this.isAskDisabled) {
            return;
        }

        this.isQuestionLoading = true;
        this.answer = null;
        this.errorMessage = null;

        try {
            const result = await askQuestion({
                contentDocumentId: this.recordId,
                question: this.question.trim()
            });

            this.answer = result;
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isQuestionLoading = false;
        }
    }

    get analysisReady() {
    return !!(this.analysis && this.analysis.sections && Object.keys(this.analysis.sections).length);
}
    get isBusy() {
        return this.isLoading || this.isQuestionLoading || this.isPdfSyncing;
    }

    get isPreviewUnavailable() {
        // Preview is available when we have ANY valid document to show:
        // the synced AI PDF, the wire-returned related file, or the source file itself
        if (this.analysis && this.analysis.pdfDocumentId) {
            return false;
        }
        if (this.file && this.file.contentDocumentId) {
            return false;
        }
        return !this.recordId;
    }

    get isProcessing() {
        return (this.isLoading || this.isPdfSyncing) && !this.isDocumentReady;
    }

    get loadingMessage() {
        if (this.isLoading) return 'Building structured AI analysis...';
        if (this.isPdfSyncing) return 'Generating and attaching the PDF summary...';
        return 'Processing...';
    }

    get isAskDisabled() {
        return this.isQuestionLoading || !this.question || !this.question.trim();
    }

    get hasPatientContext() {
        if (!this.patientContext) return false;
        return !!(this.patientContext.patientName || this.patientContext.patientAge ||
                  this.patientContext.patientGender || this.patientContext.organizationName);
    }

    get patientName() {
        return this.patientContext?.patientName || '—';
    }

    get patientAge() {
        return this.patientContext?.patientAge ? this.patientContext.patientAge + ' yrs' : '—';
    }

    get patientGender() {
        return this.patientContext?.patientGender || '—';
    }

    get organizationName() {
        return this.patientContext?.organizationName || '—';
    }

    get hasPatientOverview() {
        if (!this.patientContext) return false;
        return !!(this.patientContext.patientName || this.patientContext.patientAge ||
                  this.patientContext.patientGender);
    }

    get hasOrganization() {
        return !!(this.patientContext?.organizationName);
    }

    // Only surface tabs whose underlying AI section actually has content.
    // Mirrors the PDF's `rendered="{!NOT(ISBLANK(...))}"` conditional rendering.
    get tabItems() {
        const sections = this.analysis?.sections || {};
        return TABS
            .filter(tab => !isSectionBlank(sections[tab.id]))
            .map(tab => ({
                ...tab,
                cssClass: tab.id === this.activeTab ? 'tab-btn active' : 'tab-btn',
                dotStyle: `background-color:${tab.dotColor};`
            }));
    }

    get activeTabLabel() {
        const matched = TABS.find(tab => tab.id === this.activeTab);
        return matched ? matched.label : 'Summary';
    }

    get activeContent() {
        if (!this.analysisReady) {
            return '';
        }

        return this.analysis.sections[this.activeTab] || '<p>No information available for this section.</p>';
    }

    get formattedAnswer() {
        return this.markdownToHtml(this.answer);
    }

    get hasTagGroups() {
        return this.decoratedTagGroups.length > 0;
    }

    get decoratedTagGroups() {
        const groups = this.analysis?.tagGroups || [];

        return groups.map((group, index) => ({
            ...group,
            groupKey: `${group.category}-${index}`,
            themeClass: TAG_THEME_CLASSES[index % TAG_THEME_CLASSES.length],
            tagItems: (group.tags || []).map((tag, tagIndex) => ({
                label: tag,
                key: `${group.category}-${tag}-${tagIndex}`
            }))
        }));
    }

    get keyFieldGroups() {
    const fields = this.analysis?.keyFields || [];
    const grouped = {};

    fields.forEach((field, index) => {
        // Skip fields with empty/blank values
        if (!field.value || !field.value.trim()) {
            return;
        }

        const groupName = field.groupName || 'Extracted Fields';

        if (!grouped[groupName]) {
            grouped[groupName] = {
                name: groupName,
                iconName: GROUP_ICON_MAP[groupName] || GROUP_ICON_MAP['Extracted Fields'],
                items: []
            };
        }

        grouped[groupName].items.push({
            ...field,
            key: `${groupName}-${field.label}-${index}`
        });
    });

    return Object.values(grouped);
}

    get hasKeyFieldGroups() {
        return this.keyFieldGroups.length > 0;
    }

    get stats() {
        const sections = this.analysis?.sections || {};
        const sectionCount = Object.values(sections).filter(Boolean).length;
        const tagCount = (this.analysis?.tagGroups || []).reduce(
            (total, group) => total + ((group.tags || []).length),
            0
        );
        const fieldCount = (this.analysis?.keyFields || []).length;

        return [
            { id: 'sections', label: 'Sections', value: sectionCount, iconName: 'utility:table' },
            { id: 'tags', label: 'Tags', value: tagCount, iconName: 'utility:tag' },
            { id: 'fields', label: 'Key Fields', value: fieldCount, iconName: 'utility:record' }
        ];
    }

    markdownToHtml(text) {
        if (!text) {
            return '';
        }

        let html = text;

        html = html.replace(/&/g, '&amp;');
        html = html.replace(/</g, '&lt;');
        html = html.replace(/>/g, '&gt;');

        html = html.replace(/^###\s+(.+)$/gm, '<h4>$1</h4>');
        html = html.replace(/^##\s+(.+)$/gm, '<h3>$1</h3>');
        html = html.replace(/^#\s+(.+)$/gm, '<h2>$1</h2>');

        html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
        html = html.replace(/\*(.*?)\*/g, '<em>$1</em>');

        html = html.replace(/^\d+\.\s+(.+)$/gm, '<li class="ordered">$1</li>');
        html = html.replace(/^[\-\*]\s+(.+)$/gm, '<li>$1</li>');

        html = html.replace(/(<li class="ordered">[\s\S]*?<\/li>)/g, '<ol>$1</ol>');
        html = html.replace(/(<li>(?! class="ordered")[\s\S]*?<\/li>)/g, '<ul>$1</ul>');

        html = html.replace(/\n{2,}/g, '<br/><br/>');
        html = html.replace(/\n/g, '<br/>');
        html = html.replace(/<\/ol><br\/><ol>/g, '');
        html = html.replace(/<\/ul><br\/><ul>/g, '');

        return html;
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

    reduceErrors(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (typeof error === 'string') {
            return error;
        }

        if (error.body) {
            if (typeof error.body.message === 'string') {
                return error.body.message;
            }

            if (typeof error.body === 'string') {
                return error.body;
            }
        }

        if (error.message) {
            return error.message;
        }

        return JSON.stringify(error);
    }
}