import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, onError, isEmpEnabled } from 'lightning/empApi';
import getActivities from '@salesforce/apex/ActivityTimelineController.getActivities';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import smsIcon from '@salesforce/resourceUrl/smsIcon';
import SMSrangerLogo from '@salesforce/resourceUrl/SMSrangerLogo';
import VoiceCallIcon from '@salesforce/resourceUrl/VoiceCallIcon';
// Your Platform Event channel
const TIMELINE_REFRESH_CHANNEL = '/event/Activity_Timeline_Refresh__e';

const ICON_MAP = {
    Task: 'standard:task',
    Event: 'standard:event',
    Email: 'standard:email',
    MetriportCases: 'standard:case_change_status',
    PortalMessages: 'standard:case',
    Call: 'standard:log_a_call',
    MessagingSession:'standard:coaching',
    VoiceCall: null,
    MessageHistory: null,
    CallHistory: null,
    AiCallHistory: 'standard:call'
};

export default class ActivityTimeline extends NavigationMixin(LightningElement) {
    @api recordId;

    @track activities = [];
    @track filters = {
        Task: true, Event: true, Email: true, MetriportCases: true, PortalMessages: true, Call: true,
        MessagingSession: true, VoiceCall: true, MessageHistory: false, CallHistory: true, AiCallHistory: true
    };

    smsIcon = smsIcon;
    smsLogo = SMSrangerLogo;
    VoiceCallIcon = VoiceCallIcon;

    pageSize = 10;
    offset = 0;
    allLoaded = false;
    subscription = null;
    isLoading = false;
    hasSubscriptionError = false;

    connectedCallback() {
        console.log('ActivityTimeline connected, recordId:', this.recordId);
        
        // Check EMP API status
        isEmpEnabled().then(enabled => {
            console.log('EMP API Enabled:', enabled);
            if (!enabled) {
                console.warn('EMP API not enabled - real-time updates will not work');
                this.hasSubscriptionError = true;
            }
        }).catch(error => {
            console.error('Error checking EMP status:', error);
        });
        
        this.loadActivities();
        this.subscribeToPlatformEvent();
        this.registerErrorListener();
    }

    disconnectedCallback() {
        this.unsubscribeFromPlatformEvent();
    }

    registerErrorListener() {
        onError(error => {
            console.error('EMP API Error:', error);
            this.hasSubscriptionError = true;
        });
    }

    normalizeId(id) {
        if (!id) return id;
        return id.length > 15 ? id.substring(0, 15) : id;
    }

    async subscribeToPlatformEvent() {
        console.log('Attempting to subscribe to:', TIMELINE_REFRESH_CHANNEL);
        
        if (!this.recordId) {
            console.error('Cannot subscribe: recordId is null');
            return;
        }

        const messageHandler = (response) => {
            console.log('Platform Event received:', response);
            
            try {
                const payload = response.data.payload;
                const eventRecordId = payload.Record_Id__c;
                
                console.log('Event details:', {
                    eventRecordId: eventRecordId,
                    currentRecordId: this.recordId,
                    normalizedEvent: this.normalizeId(eventRecordId),
                    normalizedCurrent: this.normalizeId(this.recordId)
                });
                
                // Check if this event is for the current record
                if (eventRecordId && 
                    this.normalizeId(eventRecordId) === this.normalizeId(this.recordId)) {
                    
                    console.log('Event matches current record! Refreshing timeline...');
                    
                    // Show toast notification
                    //this.showToast('New activity detected', 'Refreshing timeline...', 'success');
                    
                    // Refresh the timeline
                    this.refreshTimeline();
                } else {
                    console.log('Event does not match current record, ignoring...');
                }
            } catch (error) {
                console.error('Error processing Platform Event:', error);
            }
        };

        try {
            this.subscription = await subscribe(
                TIMELINE_REFRESH_CHANNEL,
                -1,
                messageHandler
            );
            
            console.log('Successfully subscribed to Platform Event:', this.subscription);
            this.hasSubscriptionError = false;
            
        } catch (error) {
            console.error('Failed to subscribe to Platform Event:', error);
            this.hasSubscriptionError = true;
            
            // Try alternative subscription method
            try {
                this.subscription = await subscribe(
                    TIMELINE_REFRESH_CHANNEL,
                    -1,
                    messageHandler,
                    (subscriptionError) => {
                        console.error('Subscription error callback:', subscriptionError);
                        this.hasSubscriptionError = true;
                    }
                );
                console.log('Subscription successful with error callback');
                this.hasSubscriptionError = false;
            } catch (retryError) {
                console.error('Retry also failed:', retryError);
            }
        }
    }

    unsubscribeFromPlatformEvent() {
        if (this.subscription) {
            unsubscribe(this.subscription, (result) => {
                console.log('Unsubscribed from Platform Event:', result);
            });
            this.subscription = null;
        }
    }

    refreshTimeline() {
        console.log('Refreshing timeline...');
        
        // Reset pagination
        this.offset = 0;
        this.allLoaded = false;
        
        // Clear current activities
        this.activities = [];
        
        // Reload activities
        this.loadActivities();
    }

    async loadActivities() {
        if (this.isLoading || this.allLoaded) return;

        this.isLoading = true;

        try {
            const result = await getActivities({
                recordId: this.recordId,
                limitSize: this.pageSize,
                offsetSize: this.offset
            });

            const rows = result || [];

            if (rows.length < this.pageSize) {
                this.allLoaded = true;
            }

            this.offset += rows.length;

            const mapped = rows.map(row => ({
                ...row,
                iconName: ICON_MAP[row.type] || null,
                iconUrl:
                    //row.type === 'MessagingSession' ? this.smsIcon :
                    row.type === 'VoiceCall' ? this.VoiceCallIcon :
                    row.type === 'MessageHistory' ? this.smsIcon :
                    row.type === 'CallHistory' ? this.VoiceCallIcon :
                    null,
                formattedDate: row.createdDate
                    ? new Date(row.createdDate).toLocaleString()
                    : ''
            }));

            this.activities = [...this.activities, ...mapped];
        } catch (error) {
            console.error('Error loading activities', error);
            this.showToast('Error', 'Failed to load activities', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        const toastEvent = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(toastEvent);
    }

    // Add this test method for debugging
    testPlatformEventSubscription() {
        console.log('=== Testing Platform Event Subscription ===');
        console.log('Current subscription:', this.subscription);
        console.log('Record ID:', this.recordId);
        console.log('Has subscription error:', this.hasSubscriptionError);
        
        // Simulate an event manually
        const testEvent = {
            data: {
                payload: {
                    Record_Id__c: this.recordId
                }
            }
        };
        
        console.log('Simulating event:', testEvent);
        this.refreshTimeline();
    }

    // Add a method to resubscribe if needed
    resubscribe() {
        console.log('Attempting to resubscribe...');
        this.unsubscribeFromPlatformEvent();
        this.hasSubscriptionError = false;
        setTimeout(() => {
            this.subscribeToPlatformEvent();
        }, 1000);
    }

    get filteredActivities() {
        return this.activities.filter(act => this.filters[act.type]);
    }

    handleFilterChange(event) {
        const type = event.target.name;
        this.filters[type] = event.target.checked;
    }

    handleClick(event) {
        const recId = event.currentTarget.dataset.id;
        const type = event.currentTarget.dataset.type;

        let objectApiName = 'Task';
        if (type === 'Event') objectApiName = 'Event';
        else if (type === 'Email') objectApiName = 'EmailMessage';
        else if (type === 'MetriportCases' || type === 'PortalMessages') objectApiName = 'Case';
        else if (type === 'MessagingSession') objectApiName = 'MessagingSession';
        else if (type === 'VoiceCall') objectApiName = 'VoiceCall';
        else if (type === 'MessageHistory') objectApiName = 'sra__Message_History__c';
        else if (type === 'CallHistory' || type === 'AiCallHistory') objectApiName = 'ccra__Call_History__c';

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recId,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    handleManualRefresh() {
        console.log('Manual refresh requested');
        this.refreshTimeline();
        this.showToast('Refreshed', 'Timeline manually refreshed', 'success');
    }
}