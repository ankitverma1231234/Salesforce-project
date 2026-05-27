import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFilesForAccount from '@salesforce/apex/AiFileNamingConventionController.getFilesForAccount';
import getRules from '@salesforce/apex/AiFileNamingConventionController.getRules';
import saveRule from '@salesforce/apex/AiFileNamingConventionController.saveRule';
import deleteRule from '@salesforce/apex/AiFileNamingConventionController.deleteRule';
import setRuleActive from '@salesforce/apex/AiFileNamingConventionController.setRuleActive';
import previewFileName from '@salesforce/apex/AiFileNamingConventionController.previewFileName';

export default class AiFileNamingConvention extends LightningElement {
    selectedAccountMeta = '';

    accountDisplayInfo = {
    primaryField: 'Name',
    additionalFields: ['PersonEmail']
};

accountMatchingInfo = {
    primaryField: { fieldPath: 'Name', mode: 'startsWith' }
};
    rules = [];

    draftRule = {};
    fileOptions = [];
    testResult = null;

    isRuleModalOpen = false;
    isTestModalOpen = false;
    isEditMode = false;
    isLoadingFiles = false;
    isLoadingRules = false;

    selectedRuleId;
    testAccountId;
    testFileId;

    criteriaModeOptions = [
        { label: 'Prompt Only', value: 'prompt_only' },
        { label: 'Tags Only', value: 'tags_only' },
        { label: 'Prompt OR Tags', value: 'prompt_or_tags' },
        { label: 'Prompt AND Tags', value: 'prompt_and_tags' }
    ];

    connectedCallback() {
        this.loadRules();
    }

    async loadRules() {
        this.isLoadingRules = true;

        try {
            this.rules = await getRules();
        } catch (error) {
            this.showToast('Error', this.reduceError(error) || 'Unable to load AI file naming rules.', 'error');
        } finally {
            this.isLoadingRules = false;
        }
    }

    get totalRules() {
        return this.rules.length;
    }

    get activeRulesCount() {
        return this.rules.filter((rule) => rule.isActive).length;
    }

    get readyForManualTestCount() {
        return this.rules.filter(
            (rule) => rule.isActive && rule.actionPrompt && (rule.criteriaPrompt || rule.tagsText)
        ).length;
    }

    get hasRules() {
        return this.ruleRows.length > 0;
    }

    get ruleModalTitle() {
        return this.isEditMode ? 'Edit Rule' : 'New Rule';
    }

    get disableTestRun() {
        return !this.selectedRuleId;
    }

    get selectedRule() {
        return this.rules.find((rule) => rule.id === this.selectedRuleId);
    }

    get selectedRuleName() {
        return this.selectedRule ? this.selectedRule.ruleName || this.selectedRule.name : 'No rule selected';
    }

    get disableStartTest() {
        return !(this.selectedRuleId && this.testAccountId && this.testFileId);
    }

    get showNoFilesMessage() {
        return this.testAccountId && !this.isLoadingFiles && this.fileOptions.length === 0;
    }

    get ruleRows() {
        return [...this.rules]
            .sort((a, b) => a.order - b.order)
            .map((rule) => {
                return {
                    ...rule,
                    isSelected: rule.id === this.selectedRuleId,
                    criteriaSummary: this.buildCriteriaSummary(rule),
                    actionSummary: this.trimText(rule.actionPrompt, 90),
                    rowClass: rule.id === this.selectedRuleId ? 'selected-row' : ''
                };
            });
    }

    createBlankRule() {
        const nextOrder = this.rules.length ? Math.max(...this.rules.map((rule) => rule.order)) + 1 : 1;

        return {
            id: null,
            name: '',
            ruleName: '',
            order: nextOrder,
            isActive: true,
            criteriaMode: 'prompt_or_tags',
            criteriaPrompt: '',
            tagsText: '',
            actionPrompt: '',
            flowApiName: '',
            lastTestLabel: 'Never tested'
        };
    }

    handleNewRule() {
        this.isEditMode = false;
        this.draftRule = this.createBlankRule();
        this.isRuleModalOpen = true;
    }

    handleEditRule(event) {
        const ruleId = event.currentTarget.dataset.id;
        const rule = this.rules.find((item) => item.id === ruleId);

        if (!rule) {
            return;
        }

        this.isEditMode = true;
        this.draftRule = { ...rule };
        this.draftRule.ruleName = this.draftRule.ruleName || this.draftRule.name || '';
        this.draftRule.name = this.draftRule.name || this.draftRule.ruleName;
        this.isRuleModalOpen = true;
    }

    handleCloseRuleModal() {
        this.isRuleModalOpen = false;
        this.draftRule = {};
    }

    handleRuleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        if (!field) return;

        const el = event.currentTarget;
        const inputType = el.getAttribute('type');
        let value;

        if (inputType === 'toggle' || inputType === 'checkbox') {
            value = el.checked;
        } else {
            value = event.detail?.value !== undefined ? event.detail.value : el.value;
        }

        if (field === 'order') {
            value = value ? Number(value) : 1;
        }

        this.draftRule = { ...this.draftRule, [field]: value };
    }

    async handleSaveRule() {
        this.syncDraftRuleFromForm();

        const validationMessage = this.validateDraftRule();

        if (validationMessage) {
            this.showToast('Validation', validationMessage, 'warning');
            return;
        }

        const normalizedRule = {
            id: this.draftRule.id || null,
            ruleName: this.draftRule.ruleName || '',
            name: this.draftRule.ruleName || '',
            order: Number(this.draftRule.order) || 1,
            isActive: this.draftRule.isActive !== false,
            criteriaMode: this.draftRule.criteriaMode || 'prompt_or_tags',
            criteriaPrompt: this.draftRule.criteriaPrompt || '',
            tagsText: this.normalizeTags(this.draftRule.tagsText),
            actionPrompt: this.draftRule.actionPrompt || '',
            flowApiName: this.draftRule.flowApiName || '',
            lastTestLabel: this.draftRule.lastTestLabel || 'Never tested'
        };

        try {
            const savedRule = await saveRule({ draftRule: JSON.parse(JSON.stringify(normalizedRule)) });
            const existingIndex = this.rules.findIndex((rule) => rule.id === savedRule.id);

            if (existingIndex > -1) {
                const updatedRules = [...this.rules];
                updatedRules[existingIndex] = savedRule;
                this.rules = updatedRules;
            } else {
                this.rules = [...this.rules, savedRule];
            }

            this.rules = [...this.rules].sort((a, b) => a.order - b.order);
            this.isRuleModalOpen = false;
            this.draftRule = {};
            this.showToast('Success', 'Rule saved successfully.', 'success');
        } catch (error) {
            this.showToast('Error', this.reduceError(error) || 'Unable to save rule.', 'error');
        }
    }

    syncDraftRuleFromForm() {
        const draftRule = {
            id: this.draftRule.id,
            name: this.draftRule.name,
            ruleName: this.draftRule.ruleName,
            order: this.draftRule.order,
            isActive: this.draftRule.isActive,
            criteriaMode: this.draftRule.criteriaMode,
            criteriaPrompt: this.draftRule.criteriaPrompt,
            tagsText: this.draftRule.tagsText,
            actionPrompt: this.draftRule.actionPrompt,
            flowApiName: this.draftRule.flowApiName,
            lastTestLabel: this.draftRule.lastTestLabel
        };

        const fieldElements = this.template.querySelectorAll('[data-field]');
        fieldElements.forEach((el) => {
            const fieldName = el.dataset.field;
            if (!fieldName) return;

            const inputType = el.getAttribute('type');
            if (inputType === 'toggle' || inputType === 'checkbox') {
                draftRule[fieldName] = el.checked;
            } else {
                const domValue = el.value;
                if (domValue !== undefined && domValue !== null) {
                    draftRule[fieldName] = domValue;
                }
            }
        });

        if (draftRule.order !== undefined && draftRule.order !== null) {
            draftRule.order = Number(draftRule.order);
        }

        draftRule.ruleName = draftRule.ruleName || draftRule.name || '';
        draftRule.name = draftRule.ruleName;
        this.draftRule = draftRule;
    }

    validateDraftRule() {
        if (!this.draftRule.ruleName || !this.draftRule.ruleName.trim()) {
            return 'Rule Name is required.';
        }

        if (!this.draftRule.order || Number(this.draftRule.order) < 1) {
            return 'Order must be 1 or greater.';
        }

        if (!this.draftRule.actionPrompt || !this.draftRule.actionPrompt.trim()) {
            return 'Action Prompt is required.';
        }

        const hasPrompt = !!(this.draftRule.criteriaPrompt && this.draftRule.criteriaPrompt.trim());
        const hasTags = !!(this.draftRule.tagsText && this.draftRule.tagsText.trim());

        switch (this.draftRule.criteriaMode) {
            case 'prompt_only':
                if (!hasPrompt) {
                    return 'Prompt Criteria is required for Prompt Only.';
                }
                break;
            case 'tags_only':
                if (!hasTags) {
                    return 'At least one tag is required for Tags Only.';
                }
                break;
            case 'prompt_or_tags':
            case 'prompt_and_tags':
                if (!hasPrompt && !hasTags) {
                    return 'Add Prompt Criteria, Tags, or both.';
                }
                if (this.draftRule.criteriaMode === 'prompt_and_tags' && (!hasPrompt || !hasTags)) {
                    return 'Prompt AND Tags requires both a Prompt Criteria and at least one tag.';
                }
                break;
            default:
                break;
        }

        return null;
    }


    normalizeTags(tagString) {
        if (!tagString) {
            return '';
        }

        return tagString
            .split(',')
            .map((tag) => tag.trim())
            .filter((tag) => tag)
            .join(', ');
    }

    async handleDeleteRule(event) {
        const ruleId = event.currentTarget.dataset.id;

        try {
            await deleteRule({ ruleId });
            this.rules = this.rules.filter((rule) => rule.id !== ruleId);

            if (this.selectedRuleId === ruleId) {
                this.selectedRuleId = null;
            }

            this.showToast('Deleted', 'Rule removed.', 'success');
        } catch (error) {
            this.showToast('Error', this.reduceError(error) || 'Unable to delete rule.', 'error');
        }
    }

    async handleToggleActive(event) {
        const ruleId = event.currentTarget.dataset.id;
        const isActive = event.target.checked;

        this.rules = this.rules.map((rule) => {
            if (rule.id === ruleId) {
                return {
                    ...rule,
                    isActive
                };
            }

            return rule;
        });

        try {
            const updatedRule = await setRuleActive({ ruleId, isActive });
            this.rules = this.rules.map((rule) => (rule.id === updatedRule.id ? updatedRule : rule));
        } catch (error) {
            this.showToast('Error', this.reduceError(error) || 'Unable to update rule status.', 'error');
            await this.loadRules();
        }
    }

    handleSelectRule(event) {
        this.selectedRuleId = event.target.value;
    }

    handleOpenTestRun() {
    if (!this.selectedRuleId) {
        this.showToast('Select Rule', 'Please select one rule first.', 'warning');
        return;
    }

    this.testAccountId = null;
    this.testFileId = null;
    this.fileOptions = [];
    this.testResult = null;
    this.selectedAccountMeta = '';
    this.isTestModalOpen = true;
}

    handleCloseTestModal() {
    this.isTestModalOpen = false;
    this.testResult = null;
    this.testAccountId = null;
    this.testFileId = null;
    this.fileOptions = [];
    this.selectedAccountMeta = '';
}

  async handleAccountChange(event) {
    this.testAccountId = event.detail.recordId;
    this.testFileId = null;
    this.fileOptions = [];
    this.testResult = null;

    if (!this.testAccountId) {
        this.selectedAccountMeta = '';
        return;
    }

    this.selectedAccountMeta = `Selected Account Id: ${this.testAccountId}`;
    this.isLoadingFiles = true;

    try {
        const results = await getFilesForAccount({ accountId: this.testAccountId });
        this.fileOptions = (results || []).map((item) => {
            return {
                label: item.label,
                value: item.value
            };
        });
    } catch (error) {
        this.showToast(
            'Error',
            this.reduceError(error) || 'Unable to load files for the selected account.',
            'error'
        );
    } finally {
        this.isLoadingFiles = false;
    }
}

    handleFileChange(event) {
        this.testFileId = event.detail.value;
        this.testResult = null;
    }

    async handleStartTest() {
        const selectedRule = this.selectedRule;
        const selectedFile = this.fileOptions.find((option) => option.value === this.testFileId);

        if (!selectedRule || !selectedFile) {
            this.showToast('Incomplete', 'Select a rule, account, and file first.', 'warning');
            return;
        }

        try {
            this.testResult = await previewFileName({
                ruleId: selectedRule.id,
                accountId: this.testAccountId,
                contentDocumentId: selectedFile.value
            });
            await this.loadRules();
        } catch (error) {
            this.showToast('Error', this.reduceError(error) || 'Unable to preview file name.', 'error');
        }
    }

    buildCriteriaSummary(rule) {
        const labels = {
            prompt_only: 'Prompt only',
            tags_only: 'Tags only',
            prompt_or_tags: 'Prompt OR Tags',
            prompt_and_tags: 'Prompt AND Tags'
        };

        const promptFlag = rule.criteriaPrompt ? 'Prompt added' : 'No prompt';
        const tagFlag = rule.tagsText ? 'Tags added' : 'No tags';

        return `${labels[rule.criteriaMode]} - ${promptFlag} - ${tagFlag}`;
    }

    getCriteriaExplanation(rule) {
        const labels = {
            prompt_only: 'Matched by prompt criteria only',
            tags_only: 'Matched by tag criteria only',
            prompt_or_tags: 'Matched by prompt or tag criteria',
            prompt_and_tags: 'Matched by prompt and tag criteria'
        };

        return labels[rule.criteriaMode];
    }

    trimText(text, maxLength) {
        if (!text) {
            return '';
        }

        return text.length > maxLength ? `${text.substring(0, maxLength)}...` : text;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }

        if (typeof error?.body?.message === 'string') {
            return error.body.message;
        }

        return error?.message;
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
}