import { LightningElement, wire } from 'lwc';
import publishPlatformEvent from '@salesforce/apex/PublishMedicationEvent.publishMedicationEvent';

export default class LoginActivity extends LightningElement {
    userData;



    connectedCallback() {
        console.log('Inside Login Acivity');
        this.publishMedicationEvent();
    }

    publishMedicationEvent() {
        publishPlatformEvent()
            .then(result => {
            })
            .catch(error => {
                console.error('publishMedicationEvent:', error);
            });
    }

    // async beginPlatformEventInvokation() {
    //     try {
    //         await this.loadUserDetails(); // wait for user data
    //         this.publishAthenaEvent();    // then publish
    //     } catch (error) {
    //         console.error('Initialization error:', error);
    //     }
    // }

    // loadUserDetails() {
    //     return getUserDetails()
    //         .then(result => {
    //             this.userData = result;
    //             console.log('this.userData : ', JSON.parse(JSON.stringify(this.userData)));
    //         })
    //         .catch(error => {
    //             console.error('Error fetching user record:', error);
    //             throw error;
    //         });
    // }

    // get athenaIdValue() {
    //     return this.userData?.Contact?.Account?.Athena_Patient_Id__c ?? undefined;
    // }

    // publishAthenaEvent() {
    //     if (this.athenaIdValue) {
    //         publishEvent({ athenaId: this.athenaIdValue })
    //             .then(() => console.log('Event published successfully'))
    //             .catch(error => console.error('Error publishing event:', error));
    //     }
    // }

    // @wire(getRecord, { recordId: ID, fields: FIELDS })
    // wiredUser({ error, data }) {
    //     if (data) {
    //         this.userData = data;
    //         console.log('this.userData : ', JSON.parse(JSON.stringify(this.userData)));
    //         if (this.firePlatformEvent) {
    //             this.publishAthenaEvent();
    //         }
    //     } else if (error) {
    //         console.error('Error fetching user record:', error);
    //     }
    // }

    // get athenaIdValue() {
    //     return this.userData ? getFieldValue(this.userData, ATHENA_FIELD) : undefined;
    // }

    // get firePlatformEvent() {
    //     const medicationEvent = this.userData ? getFieldValue(this.userData, MEDICATION_EVENT_FIELD) : null;
    //     const lastLoginDateTime = this.userData ? new Date(getFieldValue(this.userData, LAST_LOGIN_DATE)) : null;
    //     const currentDateTime = new Date();

    //     const lastLoginDate = lastLoginDateTime.getDate() + '/' + lastLoginDateTime.getMonth() + '/' + lastLoginDateTime.getFullYear();
    //     const currentDate = currentDateTime.getDate() + '/' + currentDateTime.getMonth() + '/' + currentDateTime.getFullYear();

    //     console.log('medicationEvent : ', medicationEvent, ' lastLoginDate : ',
    //         lastLoginDate, ' currentDate : ', currentDate);

    //     if ((lastLoginDate != currentDate) || (lastLoginDate == currentDate && !medicationEvent)) {
    //         console.log('Fire Platform Event ');
    //         return true;
    //     } else {
    //         return false;
    //     }
    // }


}