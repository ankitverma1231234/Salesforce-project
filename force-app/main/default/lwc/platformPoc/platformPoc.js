import { LightningElement } from 'lwc';
import { subscribe, onError } from 'lightning/empApi';

export default class PlatformPoc extends LightningElement {
    channelNameOutbound = '/event/ccra__Call_History_Status__e';
    connectedCallback() {
        this.handleOutboundSubscribe();
        // Define the channel to subscribe to
       
    }
        handleOutboundSubscribe() {
    const channel = '/event/ccra__Call_History_Status__e';

    subscribe(channel, -1, (response) => {
        console.log("OUTBOUND EVENT RECEIVED: ", response);
        
        const payload = response.data.payload;
console.log("Payload: ", payload);
        // remove matching condition for testing
      

      
    })
    .then((resp) => console.log("Subscribed to "+ channel));
}
}