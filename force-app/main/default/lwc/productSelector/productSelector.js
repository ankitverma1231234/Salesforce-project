import { LightningElement, wire, track } from 'lwc';
import getProducts from '@salesforce/apex/ProductController.getProducts';
import createPayment from '@salesforce/apex/ProductController.createPayment';
import getPayment from '@salesforce/apex/ProductController.getPayment';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createLeadAndTask from '@salesforce/apex/ProductController.createLeadAndTask';
import createMemberPersonAccount from '@salesforce/apex/ProductController.createMemberPersonAccount';
import getCountryStatePicklists from '@salesforce/apex/ProductController.getCountryStatePicklists';

export default class ProductTable extends LightningElement {
    @track products = [];
    @track selectedRows = [];
    @track paymentRecId = '';
    @track paymentLink = '';
    @track registrationType = 'Self Registration';
    @track showMemberDetailsForm = false;
    memberFirstName = '';
    memberLastName = '';
    memberEmail = '';
    memberPhone = '';
    //memberShippingAddress = '';
    successMessage = '';
    errorMessage = '';

    //@track countryOptions = [];
    @track stateOptions = [];
    stateMap = {};

    memberStreet = '';
    memberCity = '';
    memberCountry = 'United States';
    memberState = '';
    memberZipCode = '';
    showPaymentLinkButton = false;
    showSubmitDetailsButton = false;
 

    columns = [
        { label: 'Name', fieldName: 'Name' },
        { label: 'Description', fieldName: 'Description' }
    ];

   
    
    registrationTypeOptions = [
        { label: 'Self Registration', value: 'Self Registration' },
        { label: 'Register on Behalf of Someone Else', value: 'Register on Behalf of Someone Else' }
    ];
    countryOptions = [
        { label: 'United States', value: 'United States' }
    ];

    /*connectedCallback() {
        
        if (!this.memberCountry) {
            this.memberCountry = 'United States';
        }
    }*/


    @wire(getProducts)
    wiredProducts({ error, data }) {
        if (data) {
            this.products = data;
        } else if (error) {
            console.error('Error fetching products:', error);
        }
    }

    @wire(getCountryStatePicklists)
    wiredPicklistData({ data, error }) {
        if (data) {
            console.log('dataCountry>>'+JSON.stringify(data));
            /*this.countryOptions = data.countries.map(country => ({
                label: country.label,
                value: country.value
            }));*/
            this.stateOptions = data.states.map(state => ({
                label: state.label,
                value: state.value
            }));
        } else if (error) {
            console.error('Error fetching picklist data:', error);
        }
    }

    /*handleCountryChange(event) {
        //this.selectedCountry = event.detail.value;

        // Filter state options based on selected country
        this.stateOptions = this.stateOptions.filter(state => {
            // Assuming states are related to countries based on your org setup
            return state.value;
        });

        this.selectedState = ''; // Reset state when country changes
    }*/

    handleStateChange(event) {
        console.log('eventState'+JSON.stringify(event.detail));
        this.selectedState = event.detail.value;
        this.memberState = event.detail.value;
    }

    // Handle input field changes
    handleMemberInputChange(event) {
        // Check if the input is lightning-input-address
        if (event.target.tagName === 'LIGHTNING-COMBOBOX') {
            const address = event.detail;
            //const prevCountry = this.memberCountry;
            //this.memberStreet = address.memberStreet;
            //this.memberCity = address.city;
            //this.memberCountry = address.country;
            console.log('state>>>'+this.selectedState);
            this.memberState = this.selectedState;
            //this.memberZipCode = address.postalCode;
            console.log('Address:', address);
    
            // 👉 Check if country changed → update state picklist
            /*if (address.country !== prevCountry) {
                this.stateOptions = this.stateMap[address.country]?.map(state => ({
                    label: state,
                    value: state
                })) || [];
                // Reset selected state if country changed
                this.memberState = '';
            }
    
        } else {*/
        }
        else{
            const field = event.target.dataset.field;
            const value = event.target.value;
    
            if (field === 'firstName') {
                this.memberFirstName = value;
            } else if (field === 'lastName') {
                this.memberLastName = value;
            } else if (field === 'email') {
                this.memberEmail = value;
            } else if (field === 'phone') {
                this.memberPhone = value;
            }else if(field === 'street'){
                this.memberStreet = value;
            }else if(field === 'country'){
                this.memberCountry = value;
            }else if(field === 'zipcode'){
                this.memberZipCode = value;
            }else if(field === 'city'){
                this.memberCity = value;
            }
        }
    }
    
    handleRegistrationTypeChange(event) {
        this.registrationType = event.detail.value;
        // Optionally: do something with this value
        console.log('Selected Registration Type:', this.registrationType);
    }
    handleEnterMemberDetails() {
        
        this.showMemberDetailsForm = true;
        if(this.selectedRows[0].Name !== 'Extended family plans'){ 
        this.showPaymentLinkButton = true;
        }
        else if(this.selectedRows[0].Name === 'Extended family plans'){
        this.showSubmitDetailsButton = true;
        } 
        /*
        if (!memberFirstName || !memberLastName || !memberEmail || !memberPhone || !memberStreet || !memberCity || !memberCountry || !memberState || !memberZipCode) {
            this.showPaymentLinkButton = true; 
        }*/
       
    }
   
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.showMemberDetailsForm = false;
        const datatable = this.template.querySelector('lightning-datatable');
    
        if (selectedRows.length > 1) {
            const latestRow = selectedRows[selectedRows.length - 1];
            datatable.selectedRows = [latestRow.Id];
            this.selectedRows = [...[latestRow]]; 
        } else {
            this.selectedRows = [...selectedRows]; 
        }
    
        console.log('Selected rows:', this.selectedRows);
    }

   

        get showEnterMemberDetailsButton() {
            if (!this.registrationType || !this.selectedRows.length) {
                return false;
            }
        
            const selectedProductName = this.selectedRows[0].Name;
        
            return (
                (this.registrationType === 'Register on Behalf of Someone Else') ||
                (selectedProductName === 'Extended family plans')
            );
        }
        
        get showCreatePaymentLinkButton() {
            if (!this.registrationType || !this.selectedRows.length) {
                return false;
            }
        
            const selectedProductName = this.selectedRows[0].Name;
        
            return (
                this.registrationType === 'Self Registration' &&
                selectedProductName !== 'Extended family plans'
            );
        }
    

    handleCreatePaymentLink() {
        console.log('Inside Payment Link');
        if (!this.selectedRows.length) {
            console.log('No product selected');
            this.showToast('No Selection', 'Please select products first.', 'warning');
            return;
        }
        
        if (this.selectedRows[0].Name != 'Extended family plans') {
            const productIds = this.selectedRows.map(prod => prod.Id);
            const registrationType =  this.registrationType; 
        
            console.log('Selected Product IDs:', productIds);
            console.log('Selected Registration Type:', registrationType);
        
            createPayment({ productIds, registrationType })
                .then(paymentId => {
                    console.log('Payment Id: ' + paymentId);
                    this.paymentRecId = paymentId;
                    this.handleGetPaymentLink();
                })
                .catch(error => {
                    console.error(error);
                });
            }
    }
    
    //Fetch Payment Link Created in the HandlePaymentLink method
    handleGetPaymentLink() {
        getPayment({ paymentId: this.paymentRecId })
            .then(paymentLink => {
                console.log('Payment Link'+paymentLink);
                this.paymentLink = paymentLink;
                window.open(paymentLink, '_self');
                //this.showToast('Payment Created', 'Payment link opened.', 'success');
            }
            )
            .catch(error => {
                console.error(error);
                this.showToast('Error', 'Failed to create payment.', 'error');
            });
    }

    //Create Member Account when registering on behalf of someone else
    createMemberAccount(){
        const {
            memberFirstName,
            memberLastName,
            memberEmail,
            memberPhone,
            memberStreet,
            memberCity,
            memberCountry,
            memberState,
            memberZipCode
        } = this;
    
        console.log('Member Details:', {
            memberFirstName,
            memberLastName,
            memberEmail,
            memberPhone,
            memberStreet,
            memberCity,
            memberCountry,
            memberState,
            memberZipCode
        });

        createMemberPersonAccount({
        firstName: memberFirstName,
        lastName: memberLastName,
        email: memberEmail,
        phone: memberPhone,
        street: memberStreet,
        city: memberCity,
        state: memberState,
        postalCode: memberZipCode,
        country: memberCountry
        })
        .then((accountId) => {
            console.log('Person Account created with Id:', accountId);
            //this.showMemberDetailsForm = false;
            //this.successMessage = 'Account created. Redirecting to payment...';
            const productIds = this.selectedRows.map(prod => prod.Id);
            const registrationType =  this.registrationType; 
        
            console.log('Selected Product IDs:', productIds);
            console.log('Selected Registration Type:', registrationType);
            this.handleCreatePaymentLink();
            //this.clearFormFields();
        
        })
        .catch((error) => {
            console.error('Error creating Account:', error);
            this.showMemberDetailsForm = true;
            this.errorMessage = 'Failed to submit member details. Please try again later.';
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleSubmitMemberDetails() {
        const {
            memberFirstName,
            memberLastName,
            memberEmail,
            memberPhone,
            memberStreet,
            memberCity,
            memberCountry,
            memberState,
            memberZipCode
        } = this;
    
        console.log('Member Details:', {
            memberFirstName,
            memberLastName,
            memberEmail,
            memberPhone,
            memberStreet,
            memberCity,
            memberCountry,
            memberState,
            memberZipCode
        });
    
        if (!memberFirstName || !memberLastName || !memberEmail || !memberPhone || !memberStreet || !memberCity || !memberCountry || !memberState || !memberZipCode) {
            this.errorMessage = 'All fields are required.';
            this.successMessage = '';
            //this.showPaymentLinkButton = true;
            return;
        }
    
        this.errorMessage = '';
        this.successMessage = '';
    
        const selectedProductName = this.selectedRows.length ? this.selectedRows[0].Name : '';
    
        // CASE 1: Extended Family Plan → Lead & Task only
        if (selectedProductName === 'Extended family plans') {
            createLeadAndTask({
                firstName: memberFirstName,
                lastName: memberLastName,
                email: memberEmail,
                phone: memberPhone,
                shippingAddress: `${memberStreet}, ${memberCity}, ${memberState} ${memberZipCode}, ${memberCountry}`
            })
            .then((leadId) => {
                console.log('Lead created with Id:', leadId);
                this.showMemberDetailsForm = false;
                this.successMessage = 'Thank you for showing your interest in BatonCare. Your information has been recorded and a Care Coordinator will reach out shortly.';
                this.clearFormFields();
            })
            .catch((error) => {
                console.error('Error creating Lead & Task:', error);
                this.showMemberDetailsForm = true;
                this.errorMessage = 'Failed to submit member details. Please try again later.';
            });
    
        // CASE 2: Register on Behalf + non-extended plan → Account + Payment
        }  else {
            console.log('Self registration with non-extended plan — redirecting to payment only');
            //this.handleCreatePaymentLink();
        }
    }
    
    // Clear form fields after successful submission
    clearFormFields() {
        this.memberFirstName = '';
        this.memberLastName = '';
        this.memberEmail = '';
        this.memberPhone = '';
        this.memberStreet = '';
        this.memberCity = '';
        this.memberCountry = '';
        this.memberState = '';
        this.memberZipCode = '';
    }

    get submitButtonLabel() {
        return (this.registrationType === 'Register on Behalf of Someone Else' && this.selectedRows[0]?.Name !== 'Extended family plans') 
            ? 'Submit Member Details & Pay' 
            : 'Submit Member Details';
    }
        
       

}