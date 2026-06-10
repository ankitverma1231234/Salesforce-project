import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getInsights from '@salesforce/apex/FraFileStorageAiInsightsController.getInsights';
import askQuestion from '@salesforce/apex/FraFileStorageAiInsightsController.askQuestion';

const TABS = [
    { id: 'summary', label: 'Summary', dotColor: '#2F6FED' },
    { id: 'keyFindings', label: 'Key Findings', dotColor: '#D92D20' },
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
    { id: 'medicationReview', label: 'Medication Review', dotColor: '#7A3E9D' },
    { id: 'labVitals', label: 'Lab & Vitals', dotColor: '#1E9E5A' },
    { id: 'riskAssessment', label: 'Risk Assessment', dotColor: '#C76A00' },
    { id: 'actionItems', label: 'Action Items', dotColor: '#2F6FED' },
    { id: 'patientSummary', label: 'Patient Summary', dotColor: '#0A7C86' }
];

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

function isSectionBlank(html) {
    if (!html) return true;
    const stripped = String(html).replace(/<[^>]*>/g, '').trim().toLowerCase();
    return !stripped ||
        stripped === 'no information available for this section.' ||
        stripped === 'no information available.' ||
        stripped === 'not documented.' ||
        stripped === 'n/a' ||
        stripped === '-';
}

export default class FraFileStorageAiInsights extends LightningElement {
    @api recordId;

    @track analysis;
    @track fileInfo;
    @track patientContext;
    @track activeTab = 'summary';
    @track isLoading = true;
    @track isQuestionLoading = false;
    @track errorMessage;
    @track question = '';
    @track answer;
    @track message;
    @track status;

    connectedCallback() {
        this.loadInsights();
    }

    async loadInsights() {
        this.isLoading = true;
        this.errorMessage = null;
        this.message = null;

        try {
            const result = await getInsights({ fileStorageId: this.recordId });
            this.status = result?.status;
            this.message = result?.message;
            this.fileInfo = result?.fileInfo;
            this.patientContext = result?.patientContext;

            if (result?.hasInsights) {
                this.hydrateAnalysis(result);
            } else {
                this.analysis = null;
            }
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
            this.analysis = null;
        } finally {
            this.isLoading = false;
        }
    }

    hydrateAnalysis(raw) {
        const parsed = {
            analysisTitle: raw.analysisTitle || 'Saved AI Analysis',
            sections: raw.sections || {},
            tagGroups: Array.isArray(raw.tagGroups) ? raw.tagGroups : [],
            keyFields: Array.isArray(raw.keyFields) ? raw.keyFields : []
        };

        this.analysis = parsed;
        if (isSectionBlank(parsed.sections[this.activeTab])) {
            const firstVisible = TABS.find((tab) => !isSectionBlank(parsed.sections[tab.id]));
            this.activeTab = firstVisible ? firstVisible.id : 'summary';
        }
    }

    handleTabClick(event) {
        const tabId = event.currentTarget.dataset.id;
        if (tabId) {
            this.activeTab = tabId;
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
            this.answer = await askQuestion({
                fileStorageId: this.recordId,
                question: this.question.trim()
            });
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

    get showUnavailablePill() {
        return !this.analysisReady && !this.isLoading;
    }

    get hasMessage() {
        return !!this.message && !this.analysisReady;
    }

    get messageClass() {
        return this.status === 'ERROR' || this.status === 'PARSE_ERROR' ? 'error-bar' : 'info-bar';
    }

    get messageIcon() {
        return this.status === 'ERROR' || this.status === 'PARSE_ERROR' ? 'utility:error' : 'utility:info';
    }

    get isAskDisabled() {
        return this.isQuestionLoading || !this.question || !this.question.trim();
    }

    get hasPatientContext() {
        if (!this.patientContext) return false;
        return !!(this.patientContext.patientName || this.patientContext.patientAge ||
            this.patientContext.patientGender || this.patientContext.organizationName);
    }

    get hasPatientOverview() {
        if (!this.patientContext) return false;
        return !!(this.patientContext.patientName || this.patientContext.patientAge ||
            this.patientContext.patientGender);
    }

    get hasOrganization() {
        return !!this.patientContext?.organizationName;
    }

    get patientName() {
        return this.patientContext?.patientName || '-';
    }

    get patientAge() {
        return this.patientContext?.patientAge ? `${this.patientContext.patientAge} yrs` : '-';
    }

    get patientGender() {
        return this.patientContext?.patientGender || '-';
    }

    get organizationName() {
        return this.patientContext?.organizationName || '-';
    }

    get tabItems() {
        const sections = this.analysis?.sections || {};
        return TABS
            .filter((tab) => !isSectionBlank(sections[tab.id]))
            .map((tab) => ({
                ...tab,
                cssClass: tab.id === this.activeTab ? 'tab-btn active' : 'tab-btn',
                dotStyle: `background-color:${tab.dotColor};`
            }));
    }

    get activeTabLabel() {
        const matched = TABS.find((tab) => tab.id === this.activeTab);
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
        const sectionCount = Object.values(sections).filter((value) => !isSectionBlank(value)).length;
        const tagCount = (this.analysis?.tagGroups || []).reduce(
            (total, group) => total + ((group.tags || []).length),
            0
        );
        const fieldCount = (this.analysis?.keyFields || []).filter((field) => field.value && field.value.trim()).length;

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
        html = html.replace(/^[\-*]\s+(.+)$/gm, '<li>$1</li>');
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