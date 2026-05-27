import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import getPersonAccount from '@salesforce/apex/caseCreationController.getPersonAccount';
import createCase from '@salesforce/apex/caseCreationController.createCase';
import getAllergies from '@salesforce/apex/caseCreationController.getAllergies';
import getMedications from '@salesforce/apex/caseCreationController.getMedications';
import getHealthConditions from '@salesforce/apex/caseCreationController.getHealthConditions';
import getHealthCareProcedures from '@salesforce/apex/caseCreationController.getHealthCareProcedures';

export default class PersonAccountCreateCase extends LightningElement {

    @api recordId;

    name; email; dob; biologicalSex; city; state; country; zipCode; street; phone; maidanname; notes;
    
    biologicalSexOptions = [
        { label: 'Male (M)', value: 'Male (M)' },
        { label: 'Female (F)', value: 'Female (F)' }
    ];

    allergies = [];
    medications = [];
    healthConditions = [];
    healthCareProcedures = [];

    selectedAllergyIds = [];
    selectedMedicationIds = [];
    selectedHealthConditionIds = [];
    selectedHealthCareProcedureIds = [];

    rowIdToObjectMap = {};

    selectedRecordId;
    selectedObjectApiName;
    isEditModalOpen = false;

    severityOptions = [
        { label: 'Low', value: 'Low' },
        { label: 'High', value: 'High' },
        { label: 'Unable to assess', value: 'Unable to assess' }
    ];

    categoryOptions = [
        { label: 'Evaluation and Management', value: 'Evaluation and Management' },
        { label: 'Anesthesia', value: 'Anesthesia' },
        { label: 'Surgery', value: 'Surgery' },
        { label: 'Radiology', value: 'Radiology' },
        { label: 'Pathology and Laboratory', value: 'Pathology and Laboratory' },
        { label: 'Medicine', value: 'Medicine' },
        { label: 'Surgical Procedure', value: 'Surgical Procedure' },
    ];

    allergyColumns = [
    { 
        label: 'Allergy', 
        fieldName: 'Combine_allergy_and_Generic__c',
        type: 'text'
    },
    { 
        label: 'Severity', 
        fieldName: 'Severity',
        type: 'text'
    },
    { 
        label: 'Reaction', 
        fieldName: 'Reaction__c',
        type: 'text'
    },
    { 
        label: 'Note', 
        fieldName: 'Note__c',
        type: 'text'
    },
    { 
        type: 'action', 
        typeAttributes: { 
            rowActions: [{ label: 'Edit', name: 'edit' }] 
        } 
    }
];

    medicationColumns = [
       // { label: 'Name', fieldName: 'Name' },
       {label:' Name',fieldName:'Medication_Name__c'},
        { label: 'Dose', fieldName: 'Dose__c' },
        { label: 'Frequency', fieldName: 'Frequency__c' },
        { label: 'Reason', fieldName: 'Reason__c' },
        {label:'Status',fieldName:'Status'},
        { type: 'action', typeAttributes: { rowActions: [{ label: 'Edit', name: 'edit' }] } }
    ];  

    healthConditionColumns = [
       // { label: 'Name', fieldName: 'Name' },
        { label: 'Medical Condition', fieldName: 'ProblemName' },
        { label: 'Notes', fieldName: 'ProblemDescription' },
         { label: 'Status', fieldName: 'ConditionStatus' },
        { type: 'action', typeAttributes: { rowActions: [{ label: 'Edit', name: 'edit' }] } }
    ];

    healthCareProcedureColumns = [
        { label: 'Name', fieldName: 'Name' },
        {label:'Date ',fieldName:'EffectiveDate'},
        {label:'Notes',fieldName:'Note__c'},
       // { label: 'Surgery Name', fieldName: 'Surgery_Name__c' },
        //{ label: 'Category', fieldName: 'Category' },
        { type: 'action', typeAttributes: { rowActions: [{ label: 'Edit', name: 'edit' }] } }
    ];

    get hasAllergies() { return this.allergies.length > 0; }
    get hasMedications() { return this.medications.length > 0; }

    get isAllergy() { return this.selectedObjectApiName === 'AllergyIntolerance'; }
    get isMedication() { return this.selectedObjectApiName === 'MedicationStatement'; }
    get isHealthCondition() { return this.selectedObjectApiName === 'HealthCondition'; }
    get isHealthCareProcedure() { return this.selectedObjectApiName === 'HealthCareProcedure'; }

    @wire(getPersonAccount, { accountId: '$recordId' })
    wiredAccount({ data }) {
        if (data) {
            this.name = data.Name;
            this.email = data.PersonEmail;
            this.dob = data.Date_of_Birth__pc;
            this.biologicalSex = data.Biological_Sex_at_Birth__c;
            this.city = data.PersonMailingCity;
            this.state = data.PersonMailingState;
            this.country = data.PersonMailingCountry;
            this.zipCode = data.PersonMailingPostalCode;
            this.street = data.PersonMailingStreet;
            this.phone = data.PersonHomePhone || data.PersonMobilePhone || '';
            this.maidanname = data.Maiden_Name__pc;
            
            console.log('biological data: ' + this.biologicalSex);
            
        }
    }

    @wire(getAllergies, { accountId: '$recordId' })
    wiredAllergies({ data }) {
        if (data) {
            this.allergies = data;
            // Default select all allergies
            this.selectedAllergyIds = data.map(r => r.Id);
            data.forEach(r => this.rowIdToObjectMap[r.Id] = 'AllergyIntolerance');
        }
    }

    @wire(getMedications, { accountId: '$recordId' })
    wiredMedications({ data }) {
        if (data) {
            this.medications = data;
            // Default select all medications
            this.selectedMedicationIds = data.map(r => r.Id);
            data.forEach(r => this.rowIdToObjectMap[r.Id] = 'MedicationStatement');
        }
    }

    @wire(getHealthConditions, { accountId: '$recordId' })
    wiredHealthConditions({ data }) {
        if (data) {
            this.healthConditions = data;
            // Default select all health conditions
            this.selectedHealthConditionIds = data.map(r => r.Id);
            data.forEach(r => this.rowIdToObjectMap[r.Id] = 'HealthCondition');
        }
    }

    @wire(getHealthCareProcedures, { accountId: '$recordId' })
    wiredHealthCareProcedures({ data }) {
        if (data) {
            this.healthCareProcedures = data;
            // Default select all healthcare procedures
            this.selectedHealthCareProcedureIds = data.map(r => r.Id);
            data.forEach(r => this.rowIdToObjectMap[r.Id] = 'HealthCareProcedure');
        }
    }

    handleChange(e) {
        this[e.target.dataset.field] = e.target.value;
    }

    handleRowAction(e) {
        if (e.detail.action.name !== 'edit') return;

        const row = e.detail.row;
        this.selectedRecordId = row.Id;
        this.selectedObjectApiName = this.rowIdToObjectMap[row.Id];
        this.editBuffer = JSON.parse(JSON.stringify(row));

        this.isEditModalOpen = true;
    }

    handleEditChange(e) {
        this.editBuffer[e.target.dataset.field] = e.target.value;
    }

    handleCreateCase() {
        console.log('Create clicked');
        console.log('Selected Allergy IDs:', this.selectedAllergyIds);
        console.log('Selected Medication IDs:', this.selectedMedicationIds);
        console.log('Selected Health Condition IDs:', this.selectedHealthConditionIds);
        console.log('Selected Healthcare Procedure IDs:', this.selectedHealthCareProcedureIds);

        createCase({
            accountId: this.recordId,
            name: this.name,
            email: this.email,
            dob: this.dob,
            biologicalSex: this.biologicalSex,
            street: this.street,
            city: this.city,
            state: this.state,
            country: this.country,
            zipCode: this.zipCode,
            phone: this.phone,
            maidanname: this.maidanname,
            notes: this.notes,
            allergyIdsJson: JSON.stringify(this.selectedAllergyIds),
            medicationIdsJson: JSON.stringify(this.selectedMedicationIds),
            healthConditionIdsJson: JSON.stringify(this.selectedHealthConditionIds),
            healthCareProcedureIdsJson: JSON.stringify(this.selectedHealthCareProcedureIds)
        })
            .then(caseId => {
                console.log('Case created:', caseId);
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Case created successfully',
                    variant: 'success'
                }));
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(error => {
                console.error('Error creating case:', error);
                let errorMessage = 'An error occurred while creating the case';
                if (error.body && error.body.message) {
                    errorMessage = error.body.message;
                } else if (error.message) {
                    errorMessage = error.message;
                }
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: errorMessage,
                    variant: 'error'
                }));
            });
    }

    handleHealthConditionSelection(event) {
        this.selectedHealthConditionIds =
            event.detail.selectedRows.map(row => row.Id);
    }

    handleHealthCareProcedureSelection(event) {
        this.selectedHealthCareProcedureIds =
            event.detail.selectedRows.map(row => row.Id);
    }

    handleAllergySelection(e) {
        this.selectedAllergyIds = e.detail.selectedRows.map(r => r.Id);
    }

    handleMedicationSelection(e) {
        this.selectedMedicationIds = e.detail.selectedRows.map(r => r.Id);
    }
}