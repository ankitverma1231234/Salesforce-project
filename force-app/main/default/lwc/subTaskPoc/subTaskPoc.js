import { LightningElement, wire } from 'lwc';
import {openTab,
    EnclosingTabId,
    openSubtab,
    getFocusedTabInfo,
    setTabLabel,
    setTabIcon,
    setTabHighlighted,
    getAllTabInfo,
    focusTab,
    disableTabClose} from 'lightning/platformWorkspaceApi';
    import { subscribe, unsubscribe } from 'lightning/empApi';

export default class SubTaskPoc extends LightningElement {
    subscription = null;
channelName = '/event/ccra__Call_History_Status__e';
  
    // existing properties…

   async handleSubtab() {
    try {
        const focusedTab = await getFocusedTabInfo();

        console.log('Focused Tab Info:', JSON.stringify(focusedTab));

        const parentId = focused.isSubtab ? focused.parentTabId : focused.tabId;

    await openSubtab({
        parentTabId: parentId,
        recordId: 'a02gL00000DufiYQAR',
        focus: true
    });
    } catch (e) {
        console.error('Error opening subtab:', JSON.stringify(e));
    }
}
connectedCallback() {
    this.handleOutboundSubscribe();
    this.subscribeToPhoneSearchEvent();
}
subscribeToPhoneSearchEvent() {
    subscribe(this.channelName, -1, (eventData) => {
        console.log('PHONE SEARCH EVENT RECEIVED: ', JSON.stringify(eventData));

        const payload = eventData.data.payload;

        const recordId = payload.ccra__Call_History_Id__c;
       

      
        this.openTab(recordId);

        // ❗ DO ANY ACTION HERE —
        // OPEN TAB, OPEN SUBTAB, UPDATE UI, CALL A METHOD, ETC.
      
    })
    .then(response => {
        console.log('Subscribed to Phone Search Event: ', response);
        this.subscription = response;
    });
}

 @wire(EnclosingTabId) enclosingTabId;

    //Open a new tab
    async openTab(recordId) {
          openTab({
            recordId: recordId, // use actual record Id
            focus: true
        })
        .then((tabId) => {
            console.log('Opened tab with ID:', tabId);
        })
        .catch(error => {
            console.error('Error opening tab:', error);
        });
       
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