import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Apex imports
import getRules from '@salesforce/apex/AiFileNamingConventionController.getRules';
import getRulesFresh from '@salesforce/apex/AiFileNamingConventionController.getRulesFresh';
import saveRule from '@salesforce/apex/AiFileNamingConventionController.saveRule';
import deleteRule from '@salesforce/apex/AiFileNamingConventionController.deleteRule';
import setRuleActive from '@salesforce/apex/AiFileNamingConventionController.setRuleActive';
import getFilesForAccount from '@salesforce/apex/AiFileNamingConventionController.getFilesForAccount';
import previewFileName from '@salesforce/apex/AiFileNamingConventionController.previewFileName';
import searchAccounts from '@salesforce/apex/AiFileNamingConventionController.searchAccounts';

export default class AiFileNamingRulesManager extends LightningElement {
    // STATE LAYER
    @track state = {
        rules: [],
        selectedRuleId: null,
        modals: {
            rule: false,
            test: false
        },
        loading: {
            rules: false,
            files: false,
            test: false,
            accounts: false
        },
        draftRule: {},
        testData: {
            accountId: null,
            accountSearchTerm: '',
            accountResults: [],
            selectedAccountName: null,
            selectedAccountEmail: null,
            showDropdown: false,
            fileId: null,
            fileOptions: [],
            result: null
        }
    };

    _searchTimeout = null;

    // SERVICE LAYER
    service = {
        fetchRules: async (forceFresh = false) => {
            try {
                this.state.loading.rules = true;
                const rules = forceFresh ? await getRulesFresh() : await getRules();
                // Reassign state to force LWC reactivity on nested rules array
                this.state = { ...this.state, rules: [...rules] };
            } catch (error) {
                this.showToast('Error', 'Failed to fetch rules: ' + error.body?.message, 'error');
            } finally {
                this.state.loading.rules = false;
            }
        },

        saveRule: async (payload) => {
            try {
                const result = await saveRule({ ruleData: payload });
                this.showToast('Success', 'Rule saved successfully', 'success');
                return result;
            } catch (error) {
                this.showToast('Error', 'Failed to save rule: ' + error.body?.message, 'error');
                throw error;
            }
        },

        deleteRule: async (ruleId) => {
            try {
                await deleteRule({ ruleId });
                this.showToast('Success', 'Rule deleted successfully', 'success');
            } catch (error) {
                this.showToast('Error', 'Failed to delete rule: ' + error.body?.message, 'error');
                throw error;
            }
        },

        toggleActive: async (ruleId, isActive) => {
            try {
                await setRuleActive({ ruleId, isActive });
            } catch (error) {
                this.showToast('Error', 'Failed to update rule status: ' + error.body?.message, 'error');
                throw error;
            }
        },

        fetchFiles: async (accountId) => {
            try {
                this.state.loading.files = true;
                this.state.testData.fileOptions = [];
                this.state.testData.fileId = null;
                const files = await getFilesForAccount({ accountId });
                this.state.testData.fileOptions = files.map(file => ({
                    label: file.Title,
                    value: file.Id
                }));
            } catch (error) {
                this.showToast('Error', 'Failed to fetch files: ' + error.body?.message, 'error');
            } finally {
                this.state.loading.files = false;
            }
        },

        searchAccounts: async (searchTerm) => {
            try {
                this.state.loading.accounts = true;
                const results = await searchAccounts({ searchTerm });
                this.state.testData.accountResults = results;
                this.state.testData.showDropdown = true;
            } catch (error) {
                this.showToast('Error', 'Failed to search accounts: ' + error.body?.message, 'error');
            } finally {
                this.state.loading.accounts = false;
            }
        },

        previewName: async (payload) => {
            try {
                this.state.loading.test = true;
                this.state.testData.result = null;
                const result = await previewFileName(payload);

                // Check for 503 in the suggested filename (error passed through)
                if (result.suggestedFileName && result.suggestedFileName.includes('HTTP 503')) {
                    result.suggestedFileName = null;
                    result.summary = 'Gemini experiencing high demand. Spikes in demand are usually temporary. Please try again later.';
                    result.isError = true;
                } else if (result.suggestedFileName && result.suggestedFileName.startsWith('Error:')) {
                    result.isError = true;
                    const errorMsg = result.suggestedFileName.replace('Error: ', '');
                    result.suggestedFileName = null;
                    result.summary = errorMsg;
                } else {
                    result.isError = false;
                }

                this.state.testData.result = result;
                if (!result.isError) {
                    this.showToast('Success', 'Test completed successfully', 'success');
                }
            } catch (error) {
                const errorMsg = error.body?.message || '';
                if (errorMsg.includes('503')) {
                    this.state.testData.result = {
                        suggestedFileName: null,
                        criteriaMatched: '',
                        actionUsed: '',
                        summary: 'Gemini experiencing high demand. Spikes in demand are usually temporary. Please try again later.',
                        isError: true
                    };
                } else {
                    this.showToast('Error', 'Test failed: ' + errorMsg, 'error');
                }
            } finally {
                this.state.loading.test = false;
            }
        }
    };

    // CONTROLLER LAYER
    async connectedCallback() {
        await this.init();
    }

    async init() {
        await this.service.fetchRules();
    }

    handleNewRule() {
        this.state.draftRule = {
            Name: '',
            Order__c: this.state.rules.length + 1,
            Is_Active__c: true,
            Criteria_Mode__c: 'prompt_only',
            Criteria_Prompt__c: '',
            Tags__c: '',
            Action_Prompt__c: ''
        };
        this.state.modals.rule = true;
    }

    handleEditRule(event) {
        const ruleId = event.target.dataset.id;
        const rule = this.state.rules.find(r => r.Id === ruleId);
        if (rule) {
            this.state.draftRule = { ...rule };
            this.state.modals.rule = true;
        }
    }

    async handleSaveRule() {
        if (!this.validateRule(this.state.draftRule)) return;

        try {
            await this.service.saveRule(this.state.draftRule);
            // Close modal and clear draft immediately
            this.state.modals.rule = false;
            this.state.draftRule = {};
            // Clear stale rules reference before re-fetching so the getter recomputes
            this.state.rules = [];
            // Re-fetch fresh data from server (bypassing LDS cache) so edits are visible
            await this.service.fetchRules(true);
        } catch (error) {
            // Error handled in service — modal stays open so user can retry
        }
    }

    async handleDeleteRule(event) {
        const ruleId = event.target.dataset.id;
        if (confirm('Are you sure you want to delete this rule?')) {
            try {
                await this.service.deleteRule(ruleId);
                this.state.rules = this.state.rules.filter(r => r.Id !== ruleId);
            } catch (error) {
                // Error handled in service
            }
        }
    }

    async handleToggleActive(event) {
        const ruleId = event.target.dataset.id;
        const isActive = event.target.checked;
        const rule = this.state.rules.find(r => r.Id === ruleId);
        if (rule) {
            rule.Is_Active__c = isActive;
            try {
                await this.service.toggleActive(ruleId, isActive);
            } catch (error) {
                rule.Is_Active__c = !isActive;
            }
        }
    }

    handleSelectRule(event) {
        this.state.selectedRuleId = event.target.value;
    }

    handleOpenTestRun() {
        if (!this.state.selectedRuleId) {
            this.showToast('Warning', 'Please select a rule first', 'warning');
            return;
        }
        this.state.testData = {
            accountId: null,
            accountSearchTerm: '',
            accountResults: [],
            selectedAccountName: null,
            selectedAccountEmail: null,
            showDropdown: false,
            fileId: null,
            fileOptions: [],
            result: null
        };
        this.state.modals.test = true;
    }

    // ── Account search handlers ──

    handleAccountSearch(event) {
        const searchTerm = event.target.value;
        this.state.testData.accountSearchTerm = searchTerm;

        if (this._searchTimeout) {
            clearTimeout(this._searchTimeout);
        }

        if (!searchTerm || searchTerm.length < 2) {
            this.state.testData.accountResults = [];
            this.state.testData.showDropdown = false;
            return;
        }

        this._searchTimeout = setTimeout(() => {
            this.service.searchAccounts(searchTerm);
        }, 300);
    }

    handleAccountSelect(event) {
        const accountId = event.currentTarget.dataset.id;
        const accountName = event.currentTarget.dataset.name;
        const selected = this.state.testData.accountResults.find(a => a.id === accountId);

        this.state.testData.accountId = accountId;
        this.state.testData.selectedAccountName = accountName;
        this.state.testData.selectedAccountEmail = selected?.email || '';
        this.state.testData.accountSearchTerm = '';
        this.state.testData.showDropdown = false;
        this.state.testData.accountResults = [];

        // Fetch files for the selected account
        this.service.fetchFiles(accountId);
    }

    handleAccountClear() {
        this.state.testData.accountId = null;
        this.state.testData.selectedAccountName = null;
        this.state.testData.selectedAccountEmail = null;
        this.state.testData.accountSearchTerm = '';
        this.state.testData.showDropdown = false;
        this.state.testData.accountResults = [];
        this.state.testData.fileOptions = [];
        this.state.testData.fileId = null;
        this.state.testData.result = null;
    }

    handleFileChange(event) {
        this.state.testData.fileId = event.target.value || event.detail?.value;
    }

    async handleStartTest() {
        if (!this.state.testData.accountId || !this.state.testData.fileId) {
            this.showToast('Warning', 'Please select an account and file', 'warning');
            return;
        }

        const payload = {
            ruleId: this.state.selectedRuleId,
            accountId: this.state.testData.accountId,
            contentDocumentId: this.state.testData.fileId
        };

        await this.service.previewName(payload);
    }

    handleCloseModal() {
        this.state.modals.rule = false;
        this.state.modals.test = false;
        this.state.draftRule = {};
        this.state.testData.result = null;
        this.state.testData.showDropdown = false;
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        } else if (event.target.type === 'number') {
            value = parseInt(value, 10);
        }
        this.state.draftRule = { ...this.state.draftRule, [field]: value };
    }

    // HELPER LAYER
    normalizeTags(tags) {
        return tags ? tags.split(',').map(tag => tag.trim()).filter(tag => tag) : [];
    }

    validateRule(rule) {
        if (!rule.Name) {
            this.showToast('Error', 'Rule Name is required', 'error');
            return false;
        }
        if (!rule.Order__c || rule.Order__c < 1) {
            this.showToast('Error', 'Order must be >= 1', 'error');
            return false;
        }
        if (!rule.Action_Prompt__c) {
            this.showToast('Error', 'Action Prompt is required', 'error');
            return false;
        }

        switch (rule.Criteria_Mode__c) {
            case 'prompt_only':
                if (!rule.Criteria_Prompt__c) {
                    this.showToast('Error', 'Criteria Prompt is required for prompt_only mode', 'error');
                    return false;
                }
                break;
            case 'tags_only':
                if (!rule.Tags__c) {
                    this.showToast('Error', 'Tags are required for tags_only mode', 'error');
                    return false;
                }
                break;
            case 'prompt_and_tags':
                if (!rule.Criteria_Prompt__c || !rule.Tags__c) {
                    this.showToast('Error', 'Both Criteria Prompt and Tags are required for prompt_and_tags mode', 'error');
                    return false;
                }
                break;
            case 'prompt_or_tags':
                if (!rule.Criteria_Prompt__c && !rule.Tags__c) {
                    this.showToast('Error', 'Either Criteria Prompt or Tags is required for prompt_or_tags mode', 'error');
                    return false;
                }
                break;
        }

        return true;
    }

    buildCriteriaSummary(rule) {
        let summary = rule.Criteria_Mode__c;
        if (rule.Criteria_Prompt__c) {
            summary += ` - Prompt: ${this.trimText(rule.Criteria_Prompt__c, 50)}`;
        }
        if (rule.Tags__c) {
            summary += ` - Tags: ${this.normalizeTags(rule.Tags__c).join(', ')}`;
        }
        return summary;
    }

    trimText(text, length) {
        return text && text.length > length ? text.substring(0, length) + '...' : text;
    }

    formatDate(dateString) {
        return dateString ? new Date(dateString).toLocaleString() : '';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // COMPUTED GETTERS
    get totalRules() {
        return this.state.rules.length;
    }

    get activeRulesCount() {
        return this.state.rules.filter(rule => rule.Is_Active__c).length;
    }

    get readyForManualTestCount() {
        return this.state.rules.filter(rule =>
            rule.Is_Active__c &&
            rule.Action_Prompt__c &&
            (rule.Criteria_Prompt__c || rule.Tags__c)
        ).length;
    }

    get ruleRows() {
        return [...this.state.rules]
            .sort((a, b) => a.Order__c - b.Order__c)
            .map(rule => ({
                ...rule,
                criteriaSummary: this.buildCriteriaSummary(rule),
                actionSummary: this.trimText(rule.Action_Prompt__c, 50),
            }));
    }

    get isRuleModalOpen() {
        return this.state.modals.rule;
    }

    get isTestModalOpen() {
        return this.state.modals.test;
    }

    get modalTitle() {
        return this.state.draftRule.Id ? 'Edit Rule' : 'New Rule';
    }

    get criteriaModeOptions() {
        return [
            { label: 'Prompt Only', value: 'prompt_only' },
            { label: 'Tags Only', value: 'tags_only' },
            { label: 'Prompt or Tags', value: 'prompt_or_tags' },
            { label: 'Prompt and Tags', value: 'prompt_and_tags' }
        ];
    }

    get showAccountDropdown() {
        return this.state.testData.showDropdown &&
            !this.state.testData.selectedAccountName;
    }

    get showTestResult() {
        return this.state.testData.result && !this.state.loading.test;
    }

    get testResultCardClass() {
        const isError = this.state.testData.result?.isError;
        return isError ? 'test-result-card test-result-card--error' : 'test-result-card';
    }

    get testResultIcon() {
        return this.state.testData.result?.isError ? 'utility:error' : 'utility:success';
    }

    get testResultTitle() {
        return this.state.testData.result?.isError ? 'Test Failed' : 'Test Result';
    }

    get isStartTestDisabled() {
        return this.state.loading.test ||
            !this.state.testData.accountId ||
            !this.state.testData.fileId;
    }
}