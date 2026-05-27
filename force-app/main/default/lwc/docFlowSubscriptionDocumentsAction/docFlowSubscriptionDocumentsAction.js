import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getRecipientInitData from '@salesforce/apex/DocFlowQuickActionController.getRecipientInitData';
import createDocFlowDocumentWithConfig from '@salesforce/apex/DocFlowQuickActionController.createDocFlowDocumentWithConfig';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

const TEMPLATE_ID = '9fe2bf58-e8b8-4c42-b276-20bcae45ed53';
const MAX_RECIPIENTS = 5;

const ROLE_OPTIONS = [
    { label: 'Signer', value: 'signer' },
    { label: 'Approver', value: 'approver' },
    { label: 'Reviewer', value: 'reviewer' },
    { label: 'Receive Copy', value: 'receive_copy' }
];

export default class DocFlowSubscriptionDocumentsAction extends LightningElement {
    @api recordId;
    pageRef;
    hasInitialized = false;

    isLoading = true;
    isSaving = false;
    activeTabValue = 'Member';

    nameOptionsRaw = [];
    emailOptionsRaw = [];
    phoneOptionsRaw = [];

    defaultMemberNameFieldApi = '';
    defaultMemberEmailFieldApi = '';
    defaultMemberPhoneFieldApi = '';

    fromAddressOptionsRaw = [];
    selectedFromAddressValue = '';

    recipientCards = [];
    recipientCounter = 0;

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        this.pageRef = currentPageReference;
        this.tryInitialize();
    }

    renderedCallback() {
        this.tryInitialize();
    }

    get roleOptions() {
        return ROLE_OPTIONS;
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
            const response = await getRecipientInitData({ accountId });

            this.nameOptionsRaw = this.sortOptions(response.nameOptions || []);
            this.emailOptionsRaw = this.sortOptions(response.emailOptions || []);
            this.phoneOptionsRaw = this.sortOptions(response.phoneOptions || []);

            this.defaultMemberNameFieldApi = this.ensureOptionValue(
                response.defaultMemberNameFieldApi || 'Name',
                this.nameOptionsRaw
            );

            this.defaultMemberEmailFieldApi = this.ensureOptionValue(
                response.defaultMemberEmailFieldApi || 'PersonEmail',
                this.emailOptionsRaw
            );

            this.defaultMemberPhoneFieldApi = this.ensureOptionValue(
                response.defaultMemberPhoneFieldApi || 'PersonMobilePhone',
                this.phoneOptionsRaw,
                false
            );

            this.fromAddressOptionsRaw = response.fromAddressOptions || [];
            this.selectedFromAddressValue = response.defaultFromAddressValue || '';

            this.resetFormState();
        } catch (error) {
            this.showToast('Please contact your DocFlow support', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleMemberActive() {
        this.activeTabValue = 'Member';
    }

    handleSurrogateActive() {
        this.activeTabValue = 'Surrogate';
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

        const newCard = this.buildRecipientCard(this.activeTabValue);
        newCard.isExpanded = true;

        this.recipientCards = this.resequence([...collapsed, newCard]);
    }

    handleResetForm() {
        this.resetFormState();
        this.selectedFromAddressValue = this.fromAddressOptionsRaw.length ? this.fromAddressOptionsRaw[0].value : '';
    }

    handleToggleCard(event) {
        const targetId = event.currentTarget.dataset.id;

        this.recipientCards = this.resequence(
            this.recipientCards.map((card) => ({
                ...card,
                isExpanded: card.id === targetId ? !card.isExpanded : false
            }))
        );
    }

    handleModeToggle(event) {
        const targetId = event.target.dataset.id;
        const section = event.target.dataset.section;
        const checked = event.target.checked;

        this.recipientCards = this.resequence(
            this.recipientCards.map((card) => {
                if (card.id !== targetId) {
                    return card;
                }

                const updated = { ...card };

                if (section === 'name') {
                    updated.nameMode = checked ? 'field' : 'manual';
                    if (checked && !updated.nameFieldApi) {
                        updated.nameFieldApi =
                            updated.type === 'Member' ? this.defaultMemberNameFieldApi : '';
                    }
                }

                if (section === 'email') {
                    updated.emailMode = checked ? 'field' : 'manual';
                    if (checked && !updated.emailFieldApi) {
                        updated.emailFieldApi =
                            updated.type === 'Member' ? this.defaultMemberEmailFieldApi : '';
                    }
                }

                if (section === 'phone') {
                    updated.phoneMode = checked ? 'field' : 'manual';
                    if (checked && !updated.phoneFieldApi) {
                        updated.phoneFieldApi =
                            updated.type === 'Member' ? this.defaultMemberPhoneFieldApi : '';
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
                if (card.id !== targetId) {
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
                if (card.id !== targetId) {
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
                if (card.id !== targetId) {
                    return card;
                }

                return {
                    ...card,
                    role: value
                };
            })
        );
    }

    handleFromAddressChange(event) {
        this.selectedFromAddressValue = event.detail.value;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSubmit() {
        const validationMessage = this.validateForm();
        if (validationMessage) {
            this.showToast('Validation Error', validationMessage, 'error');
            return;
        }

        const selectedFrom = this.selectedFromAddressOption;
        const config = {
            version: '2.0',
            fromAddress: selectedFrom
                ? {
                    value: selectedFrom.value,
                    name: selectedFrom.label,
                    email: selectedFrom.email,
                    source: selectedFrom.source
                }
                : null,
            recipients: this.recipientCards.map((card, index) => ({
                sequence: index + 1,
                routingOrder: index + 1,
                type: card.type,
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
            }))
        };

        this.isSaving = true;

        try {
            await createDocFlowDocumentWithConfig({
                accountId: this.resolvedRecordId,
                templateId: TEMPLATE_ID,
                configJson: JSON.stringify(config)
            });

            this.showToast(
                'Success',
                'DocFlow request initiated. The configuration has been saved successfully.',
                'success'
            );

            setTimeout(() => {
                this.dispatchEvent(new CloseActionScreenEvent());
            }, 700);
        } catch (error) {
            this.showToast('Please contact your DocFlow support', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    validateForm() {
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

            if (!card.type || !['Member', 'Surrogate'].includes(card.type)) {
                return `${label}: recipient type is invalid.`;
            }

            if (!card.role || !['signer', 'approver', 'reviewer', 'receive_copy'].includes(card.role)) {
                return `${label}: role is invalid.`;
            }

            if (card.nameMode === 'field') {
                if (!card.nameFieldApi) {
                    return `${label}: name field is required.`;
                }
            } else {
                if (!this.trimValue(card.nameManualValue)) {
                    return `${label}: name is required.`;
                }
            }

            if (card.emailMode === 'field') {
                if (!card.emailFieldApi) {
                    return `${label}: email field is required.`;
                }
            } else {
                const email = this.trimValue(card.emailManualValue);
                if (!email) {
                    return `${label}: email is required.`;
                }
                if (!this.isValidEmail(email)) {
                    return `${label}: email is invalid.`;
                }
            }

            if (card.phoneMode === 'field') {
                // Optional, so blank field selection is allowed.
            } else {
                const phone = this.trimValue(card.phoneManualValue);
                if (phone) {
                    const phoneError = this.validatePhone(phone);
                    if (phoneError) {
                        return `${label}: ${phoneError}`;
                    }
                }
            }
        }

        return null;
    }

    buildRecipientCard(type) {
        this.recipientCounter += 1;

        const normalizedType = type === 'Surrogate' ? 'Surrogate' : 'Member';
        const isMember = normalizedType === 'Member';

        return {
            id: `recipient-${this.recipientCounter}`,
            sequence: this.recipientCounter,
            type: normalizedType,
            role: 'signer',
            roleLabel: this.getRoleLabel('signer'),
            isExpanded: true,
            expandIcon: 'utility:chevrondown',

            nameMode: isMember ? 'field' : 'manual',
            nameFieldApi: isMember ? this.defaultMemberNameFieldApi : '',
            nameManualValue: '',

            emailMode: isMember ? 'field' : 'manual',
            emailFieldApi: isMember ? this.defaultMemberEmailFieldApi : '',
            emailManualValue: '',

            phoneMode: isMember && this.defaultMemberPhoneFieldApi ? 'field' : 'manual',
            phoneFieldApi: isMember ? (this.defaultMemberPhoneFieldApi || '') : '',
            phoneManualValue: ''
        };
    }

    resetFormState() {
        this.recipientCounter = 0;
        this.recipientCards = [this.buildRecipientCard('Member')];
        this.recipientCards = this.resequence(this.recipientCards);
    }

    resequence(cards) {
        return cards.map((card, index) => ({
            ...card,
            sequence: index + 1,
            roleLabel: this.getRoleLabel(card.role),
            expandIcon: card.isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            nameModeIsField: card.nameMode === 'field',
            emailModeIsField: card.emailMode === 'field',
            phoneModeIsField: card.phoneMode === 'field'
        }));
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