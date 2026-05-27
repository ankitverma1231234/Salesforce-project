import {track, LightningElement } from 'lwc';
import { enable, disable, addDialListener } from 'lightning/clickToDialService';

export default class CliclToDialPoc extends LightningElement {
      @track dialStatus;

   handleDial() {
    const phoneNumber = '+18005551212';
    const sforceGlobal = window.sforce || window.top?.sforce;

    if (sforceGlobal && sforceGlobal.opencti) {
        console.log('Open CTI is available');
        this.dialStatus = 'Dialing via Open CTI...';
        sforceGlobal.opencti.screenPop({
            type: sforceGlobal.opencti.SCREENPOP_TYPE.SOBJECT,
            params: { recordId: '001gL00000FkSBxQAN' },
            callback: (response) => {
                this.dialStatus = response.success
                    ? `CTI triggered for ${phoneNumber}`
                    : 'CTI call failed: ' + response.error;
            }
        });
    } else {
        this.dialStatus = 'Open CTI not available — opening tel: link';
        window.open(`tel:${phoneNumber}`);
    }
}
 enableClickToDial() {
        enable();
    }

    disableClickToDial() {
        disable();
    }

    onClickToDial() {
        addDialListener((payload) => {
            // eslint-disable-next-line no-alert
            alert(
                'This alert simulates the onClickToDial method for Open CTI in Lightning Experience. The phone number is dialed sending the following payload: ' +
                    JSON.stringify(payload)
            );
        });
    }

}