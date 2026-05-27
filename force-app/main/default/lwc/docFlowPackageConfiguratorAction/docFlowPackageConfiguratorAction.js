import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getConfiguratorInitData from '@salesforce/apex/DocFlowPackageConfiguratorController.getConfiguratorInitData';
import createDocFlowPackageDraft from '@salesforce/apex/DocFlowPackageConfiguratorController.createDocFlowPackageDraft';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

const MAX_RECIPIENTS = 5;

const ROLE_OPTIONS = [
    { label: 'Signer', value: 'signer' },
    { label: 'Approver', value: 'approver' },
    { label: 'Reviewer', value: 'reviewer' },
    { label: 'Receive Copy', value: 'receive_copy' }
];

export default class DocFlowPackageConfiguratorAction extends LightningElement {
    @api recordId;
    pageRef;
    hasInitialized = false;

    isLoading = true;
    isSaving = false;

    currentStep = 1;

    packagesRaw = [];
    selectedPackageId = '';

    nameOptionsRaw = [];
    emailOptionsRaw = [];
    phoneOptionsRaw = [];

    defaultNameFieldApi = '';
    defaultEmailFieldApi = '';
    defaultPhoneFieldApi = '';
    showReminderSettings = false;
    reminderEnabled = true;
    reminderIntervalDays = '1';
    reminderMaxCount = '3';

    fromAddressOptionsRaw = [];
    selectedFromAddressValue = '';

    recipientCards = [];
    recipientCounter = 0;

    assignmentRows = [];

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        this.pageRef = currentPageReference;
        this.tryInitialize();
    }

    renderedCallback() {
        this.tryInitialize();
    }
    get reminderIntervalOptions() {
        return [
            { label: 'Every 1 day', value: '1' },
            { label: 'Every 2 days', value: '2' },
            { label: 'Every 3 days', value: '3' },
            { label: 'Every 5 days', value: '5' },
            { label: 'Every 7 days', value: '7' }
        ];
    }

    get reminderMaxOptions() {
        return [
            { label: '1 reminder', value: '1' },
            { label: '2 reminders', value: '2' },
            { label: '3 reminders', value: '3' },
            { label: '4 reminders', value: '4' },
            { label: '5 reminders', value: '5' }
        ];
    }

    handleToggleReminderSettings() {
        this.showReminderSettings = !this.showReminderSettings;
    }

    handleReminderEnabledChange(event) {
        this.reminderEnabled = event.target.checked;
    }

    handleReminderIntervalChange(event) {
        this.reminderIntervalDays = event.detail.value;
    }

    handleReminderMaxCountChange(event) {
        this.reminderMaxCount = event.detail.value;
    }

    get resolvedRecordId() {
        if (this.recordId) {
            return this.recordId;
        }

        if (this.pageRef?.attributes?.recordId) {
            return this.pageRef.attributes.recordId;
        }

        const match = window.location.pathname.match(/\/Account\/([a-zA-Z0-9]{15,18})\//);
        return match && match[1] ? match[1] : null;
    }

    get isStepOne() {
        return this.currentStep === 1;
    }

    get isStepTwo() {
        return this.currentStep === 2;
    }

    get isStepThree() {
        return this.currentStep === 3;
    }

    get stepOneClass() {
        return `step-pill ${this.currentStep === 1 ? 'active' : ''}`;
    }

    get stepTwoClass() {
        return `step-pill ${this.currentStep === 2 ? 'active' : ''}`;
    }

    get stepThreeClass() {
        return `step-pill ${this.currentStep === 3 ? 'active' : ''}`;
    }

    get roleOptions() {
        return ROLE_OPTIONS;
    }

    get packageOptions() {
        return this.packagesRaw.map((pkg) => ({
            label: pkg.packageName,
            value: pkg.packageId
        }));
    }

    get selectedPackage() {
        return this.packagesRaw.find((pkg) => pkg.packageId === this.selectedPackageId);
    }

    get selectedPackageName() {
        return this.selectedPackage ? this.selectedPackage.packageName : '';
    }

    get nameFieldOptions() {
        return this.nameOptionsRaw.map((item) => ({
            label: `${item.label} (${item.apiName})`,
            value: item.apiName
        }));
    }

    get emailFieldOptions() {
        return this.emailOptionsRaw.map((item) => ({
            label: `${item.label} (${item.apiName})`,
            value: item.apiName
        }));
    }

    get phoneFieldOptions() {
        return this.phoneOptionsRaw.map((item) => ({
            label: `${item.label} (${item.apiName})`,
            value: item.apiName
        }));
    }

    get fromAddressOptions() {
        return this.fromAddressOptionsRaw.map((item) => ({
            label: `${item.label} <${item.email}>`,
            value: item.value
        }));
    }

    get selectedFromAddressOption() {
        return this.fromAddressOptionsRaw.find((item) => item.value === this.selectedFromAddressValue);
    }

    get assignmentRecipientOptions() {
        return this.recipientCards.map((card) => ({
            label: `Recipient ${card.sequence} - ${card.roleLabel}`,
            value: card.recipientId
        }));
    }

    async tryInitialize() {
        if (this.hasInitialized) {
            return;
        }

        const accountId = this.resolvedRecordId;
        if (!accountId) {
            return;
        }

        this.hasInitialized = true;
        await this.loadInitData(accountId);
    }

    async loadInitData(accountId) {
        this.isLoading = true;

        try {
            const response = await getConfiguratorInitData({ accountId });

            this.packagesRaw = response.packages || [];

            this.nameOptionsRaw = this.sortOptions(response.nameOptions || []);
            this.emailOptionsRaw = this.sortOptions(response.emailOptions || []);
            this.phoneOptionsRaw = this.sortOptions(response.phoneOptions || []);

            this.defaultNameFieldApi = this.ensureOptionValue(
                response.defaultNameFieldApi || 'Name',
                this.nameOptionsRaw
            );

            this.defaultEmailFieldApi = this.ensureOptionValue(
                response.defaultEmailFieldApi || 'PersonEmail',
                this.emailOptionsRaw,
                false
            );

            this.defaultPhoneFieldApi = this.ensureOptionValue(
                response.defaultPhoneFieldApi || 'PersonMobilePhone',
                this.phoneOptionsRaw,
                false
            );

            this.fromAddressOptionsRaw = response.fromAddressOptions || [];

const preferredSupportOption = this.fromAddressOptionsRaw.find(
    (item) => (item.email || '').toLowerCase() === 'support@batoncare.com'
);

this.selectedFromAddressValue = preferredSupportOption
    ? preferredSupportOption.value
    : (response.defaultFromAddressValue ||
        (this.fromAddressOptionsRaw.length ? this.fromAddressOptionsRaw[0].value : ''));

            this.resetRecipients();
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handlePackageChange(event) {
        this.selectedPackageId = event.detail.value;
        this.assignmentRows = [];
    }

    handleNextFromStepOne() {
        if (!this.selectedPackageId) {
            this.showToast('Validation Error', 'Please select a package.', 'error');
            return;
        }
        this.currentStep = 2;
    }

    handleBackToStepOne() {
        this.currentStep = 1;
    }

    handleBackToStepTwo() {
        this.currentStep = 2;
    }

    handleAddRecipient() {
        if (this.recipientCards.length >= MAX_RECIPIENTS) {
            this.showToast('Limit Reached', 'You can add up to 5 recipients only.', 'warning');
            return;
        }

        const collapsed = this.recipientCards.map((card) => ({
            ...card,
            isExpanded: false
        }));

        const newCard = this.buildRecipientCard();
        newCard.isExpanded = true;

        this.recipientCards = this.resequence([...collapsed, newCard]);
    }

    handleRemoveRecipient(event) {
        event.stopPropagation();
        const localId = event.currentTarget.dataset.id;

        this.recipientCards = this.resequence(
            this.recipientCards.filter((card) => card.localId !== localId)
        );

        this.rebuildAssignmentsPreservingValues();
    }

    handleResetRecipients() {
        this.resetRecipients();
    }

    handleToggleCard(event) {
        const targetId = event.currentTarget.dataset.id;

        this.recipientCards = this.resequence(
            this.recipientCards.map((card) => ({
                ...card,
                isExpanded: card.localId === targetId ? !card.isExpanded : false
            }))
        );
    }

    handleModeToggle(event) {
        const targetId = event.target.dataset.id;
        const section = event.target.dataset.section;
        const checked = event.target.checked;

        this.recipientCards = this.resequence(
            this.recipientCards.map((card) => {
                if (card.localId !== targetId) {
                    return card;
                }

                const updated = { ...card };

                if (section === 'name') {
                    updated.nameMode = checked ? 'field' : 'manual';
                    if (checked && !updated.nameFieldApi) {
                        updated.nameFieldApi = this.defaultNameFieldApi;
                    }
                }

                if (section === 'email') {
                    updated.emailMode = checked ? 'field' : 'manual';
                    if (checked && !updated.emailFieldApi) {
                        updated.emailFieldApi = this.defaultEmailFieldApi;
                    }
                }

                if (section === 'phone') {
                    updated.phoneMode = checked ? 'field' : 'manual';
                    if (checked && !updated.phoneFieldApi) {
                        updated.phoneFieldApi = this.defaultPhoneFieldApi;
                    }
                }

                return updated;
            })
        );
    }

    handleFieldSelectionChange(event) {
        const targetId = event.target.dataset.id;
        const section = event.target.dataset.section;
        const value = event.detail.value;

        this.recipientCards = this.resequence(
            this.recipientCards.map((card) => {
                if (card.localId !== targetId) {
                    return card;
                }

                const updated = { ...card };
                if (section === 'name') updated.nameFieldApi = value;
                if (section === 'email') updated.emailFieldApi = value;
                if (section === 'phone') updated.phoneFieldApi = value;
                return updated;
            })
        );
    }

    handleManualInputChange(event) {
        const targetId = event.target.dataset.id;
        const section = event.target.dataset.section;
        const value = event.target.value;

        this.recipientCards = this.resequence(
            this.recipientCards.map((card) => {
                if (card.localId !== targetId) {
                    return card;
                }

                const updated = { ...card };
                if (section === 'name') updated.nameManualValue = value;
                if (section === 'email') updated.emailManualValue = value;
                if (section === 'phone') updated.phoneManualValue = value;
                return updated;
            })
        );
    }

    handleRoleChange(event) {
        const targetId = event.target.dataset.id;
        const value = event.detail.value;

        this.recipientCards = this.resequence(
            this.recipientCards.map((card) => {
                if (card.localId !== targetId) {
                    return card;
                }

                return {
                    ...card,
                    role: value
                };
            })
        );

        this.rebuildAssignmentsPreservingValues();
    }

    handleFromAddressChange(event) {
        this.selectedFromAddressValue = event.detail.value;
    }

    handleNextFromStepTwo() {
        const error = this.validateRecipients();
        if (error) {
            this.showToast('Validation Error', error, 'error');
            return;
        }

        this.buildAssignmentRows();
        this.currentStep = 3;
    }

    handleAssignmentChange(event) {
        const key = event.target.dataset.key;
        const value = event.detail.value;

        this.assignmentRows = this.assignmentRows.map((row) => {
            if (row.key !== key) {
                return row;
            }
            return {
                ...row,
                recipientId: value
            };
        });
    }

async handleSaveDraft() {
    const recipientError = this.validateRecipients();
    if (recipientError) {
        this.showToast('Validation Error', recipientError, 'error');
        this.currentStep = 2;
        return;
    }

    const assignmentError = this.validateAssignments();
    if (assignmentError) {
        this.showToast('Validation Error', assignmentError, 'error');
        return;
    }

    const selectedPackage = this.selectedPackage;
    const selectedFrom = this.selectedFromAddressOption;

    const config = {
        version: '3.1',
        sourceType: 'package',
        packageId: selectedPackage.packageId,
        packageName: selectedPackage.packageName,
        fromAddress: selectedFrom
            ? {
                value: selectedFrom.value,
                name: selectedFrom.label,
                email: selectedFrom.email,
                source: selectedFrom.source
            }
            : null,
        reminderSettings: {
            enabled: this.reminderEnabled,
            intervalDays: Number(this.reminderIntervalDays),
            maxReminders: Number(this.reminderMaxCount)
        },
        recipients: this.recipientCards.map((card) => ({
            recipientId: card.recipientId,
            sequence: card.sequence,
            role: card.role,
            name: {
                mode: card.nameMode,
                fieldApi: card.nameMode === 'field' ? card.nameFieldApi : null,
                manualValue: card.nameMode === 'manual' ? this.trimValue(card.nameManualValue) : null
            },
            email: {
                mode: card.emailMode,
                fieldApi: card.emailMode === 'field' ? card.emailFieldApi : null,
                manualValue: card.emailMode === 'manual' ? this.trimValue(card.emailManualValue) : null
            },
            phone: {
                mode: card.phoneMode,
                fieldApi: card.phoneMode === 'field' ? card.phoneFieldApi : null,
                manualValue: card.phoneMode === 'manual' ? this.trimValue(card.phoneManualValue) : null
            }
        })),
        fieldAssignments: this.assignmentRows
            .filter((row) => !row.isMerge)
            .map((row) => ({
                templateId: row.templateId,
                documentName: row.documentName,
                fieldId: row.fieldId,
                fieldName: row.fieldName,
                fieldType: row.fieldType,
                required: row.required,
                recipientId: row.recipientId,
                isMerge: false
            })),
        mergeAssignments: this.assignmentRows
            .filter((row) => row.isMerge)
            .map((row) => ({
                templateId: row.templateId,
                documentName: row.documentName,
                fieldId: row.fieldId,
                fieldName: row.fieldName,
                fieldType: row.fieldType,
                required: row.required,
                recipientId: row.recipientId,
                isMerge: true,
                mergeSource: row.mergeSource || null
            }))
    };

    this.isSaving = true;

    try {
        await createDocFlowPackageDraft({
            accountId: this.resolvedRecordId,
            packageId: selectedPackage.packageId,
            packageName: selectedPackage.packageName,
            packageMetadataJson: JSON.stringify(selectedPackage),
            draftConfigJson: JSON.stringify(config)
        });

        this.showToast('Success', 'DocFlow send request initiated.', 'success');

        setTimeout(() => {
            this.dispatchEvent(new CloseActionScreenEvent());
        }, 700);
    } catch (error) {
        this.showToast('Error', this.reduceError(error), 'error');
    } finally {
        this.isSaving = false;
    }
}

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    resetRecipients() {
        this.recipientCounter = 0;
        this.recipientCards = [this.buildRecipientCard()];
        this.recipientCards = this.resequence(this.recipientCards);
        this.assignmentRows = [];
    }

    buildRecipientCard() {
        this.recipientCounter += 1;
    
        const defaultNameApi =
            this.defaultNameFieldApi ||
            (this.nameOptionsRaw.find((o) => (o.apiName || '').toLowerCase() === 'name')?.apiName || '');
    
        const defaultEmailApi =
            this.defaultEmailFieldApi ||
            (this.emailOptionsRaw.find((o) => (o.apiName || '').toLowerCase() === 'personemail')?.apiName || '');
    
        const defaultPhoneApi =
            this.defaultPhoneFieldApi ||
            (this.phoneOptionsRaw.find((o) => (o.apiName || '').toLowerCase() === 'personmobilephone')?.apiName || '');
    
        return {
            localId: `local-${this.recipientCounter}`,
            recipientId: `r${this.recipientCounter}`,
            sequence: this.recipientCounter,
            role: 'signer',
            roleLabel: this.getRoleLabel('signer'),
            isExpanded: true,
            expandIcon: 'utility:chevrondown',
            canRemove: this.recipientCounter > 1,
    
            nameMode: defaultNameApi ? 'field' : 'manual',
            nameFieldApi: defaultNameApi,
            nameManualValue: '',
    
            emailMode: defaultEmailApi ? 'field' : 'manual',
            emailFieldApi: defaultEmailApi,
            emailManualValue: '',
    
            phoneMode: defaultPhoneApi ? 'manual' : 'field',
            phoneFieldApi: defaultPhoneApi,
            phoneManualValue: ''
        };
    }

    resequence(cards) {
        return cards.map((card, index) => ({
            ...card,
            sequence: index + 1,
            canRemove: cards.length > 1,
            roleLabel: this.getRoleLabel(card.role),
            expandIcon: card.isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            nameModeIsField: card.nameMode === 'field',
            emailModeIsField: card.emailMode === 'field',
            phoneModeIsField: card.phoneMode === 'field'
        }));
    }

   buildAssignmentRows() {
    const existingMap = new Map();
    this.assignmentRows.forEach((row) => {
        existingMap.set(row.key, row.recipientId);
    });

    const packageMeta = this.selectedPackage;
    if (!packageMeta) {
        this.assignmentRows = [];
        return;
    }

    const defaultRecipientId = this.getDefaultAssignmentRecipientId();
    const rows = [];

    packageMeta.templates.forEach((tpl) => {
        (tpl.fields || []).forEach((fld) => {
            const key = `${tpl.templateId}::${fld.fieldId}`;

            rows.push({
                key,
                templateId: tpl.templateId,
                documentName: tpl.documentName,
                fieldId: fld.fieldId,
                fieldName: fld.fieldName,
                fieldType: fld.fieldType,
                required: !!fld.required,
                isMerge: !!fld.isMerge,
                mergeSource: fld.mergeSource || null,
                mergeSourceLabel:
                    fld.isMerge && fld.mergeSource
                        ? `${fld.mergeSource.objectName}.${fld.mergeSource.fieldName}`
                        : '',
                recipientId: existingMap.get(key) || defaultRecipientId
            });
        });
    });

    this.assignmentRows = rows;
}

    rebuildAssignmentsPreservingValues() {
        if (this.currentStep !== 3 || !this.assignmentRows.length) {
            return;
        }
        this.buildAssignmentRows();
    }

    getDefaultAssignmentRecipientId() {
        const signer = this.recipientCards.find((card) => card.role === 'signer');
        if (signer) {
            return signer.recipientId;
        }
        return this.recipientCards.length ? this.recipientCards[0].recipientId : null;
    }

    validateRecipients() {
        if (!this.selectedPackageId) {
            return 'Please select a package.';
        }

        if (!this.selectedFromAddressValue) {
            return 'From address is required.';
        }

        if (!this.recipientCards.length) {
            return 'At least one recipient is required.';
        }

        if (this.recipientCards.length > MAX_RECIPIENTS) {
            return 'You can add up to 5 recipients only.';
        }

        for (let i = 0; i < this.recipientCards.length; i++) {
            const card = this.recipientCards[i];
            const label = `Recipient ${i + 1}`;

            if (!card.role || !['signer', 'approver', 'reviewer', 'receive_copy'].includes(card.role)) {
                return `${label}: role is invalid.`;
            }

            if (card.nameMode === 'field') {
                if (!card.nameFieldApi) {
                    return `${label}: name field is required.`;
                }
            } else if (!this.trimValue(card.nameManualValue)) {
                return `${label}: name is required.`;
            }

            let hasEmail = false;
            let hasPhone = false;

            if (card.emailMode === 'field') {
                hasEmail = !!card.emailFieldApi;
            } else {
                const email = this.trimValue(card.emailManualValue);
                if (email) {
                    if (!this.isValidEmail(email)) {
                        return `${label}: email is invalid.`;
                    }
                    hasEmail = true;
                }
            }

            if (card.phoneMode === 'field') {
                hasPhone = !!card.phoneFieldApi;
            } else {
                const phone = this.trimValue(card.phoneManualValue);
                if (phone) {
                    const phoneError = this.validatePhone(phone);
                    if (phoneError) {
                        return `${label}: ${phoneError}`;
                    }
                    hasPhone = true;
                }
            }

            if (!hasEmail && !hasPhone) {
                return `${label}: at least one of email or phone is required.`;
            }
        }

        return null;
    }

    validateAssignments() {
        const validRecipientIds = new Set(this.recipientCards.map((card) => card.recipientId));

        for (let i = 0; i < this.assignmentRows.length; i++) {
            const row = this.assignmentRows[i];
            if (!row.recipientId || !validRecipientIds.has(row.recipientId)) {
                return `Field assignment is missing for ${row.documentName} - ${row.fieldName}.`;
            }
        }

        return null;
    }

    ensureOptionValue(preferredApi, options, fallbackToFirst = true) {
        if (preferredApi && options.some((item) => item.apiName === preferredApi)) {
            return preferredApi;
        }
        return fallbackToFirst && options.length ? options[0].apiName : '';
    }

    sortOptions(options) {
        return [...options].sort((a, b) => {
            const aLabel = (a.label || '').toLowerCase();
            const bLabel = (b.label || '').toLowerCase();
            return aLabel.localeCompare(bLabel);
        });
    }

    getRoleLabel(value) {
        const match = ROLE_OPTIONS.find((item) => item.value === value);
        return match ? match.label : 'Signer';
    }

    trimValue(value) {
        return value ? value.trim() : '';
    }

    isValidEmail(value) {
        const email = this.trimValue(value);
        const regex = /^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$/;
        return regex.test(email);
    }

    validatePhone(value) {
        const raw = this.trimValue(value);
        if (!raw) {
            return null;
        }

        const hasLeadingPlus = raw.startsWith('+');
        let cleaned = raw.replace(/[\s\-().]/g, '');

        if (hasLeadingPlus) {
            cleaned = '+' + cleaned.substring(1).replace(/[^0-9]/g, '');
        } else {
            cleaned = cleaned.replace(/[^0-9]/g, '');
        }

        const digitsOnly = hasLeadingPlus ? cleaned.substring(1) : cleaned;

        if (!/^\d+$/.test(digitsOnly)) {
            return 'phone is invalid.';
        }

        if (digitsOnly.length < 7 || digitsOnly.length > 15) {
            return 'phone must contain between 7 and 15 digits.';
        }

        return null;
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