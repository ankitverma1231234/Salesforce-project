import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

export default class CreateCaseLauncher extends LightningElement {

    recordId;

    @wire(CurrentPageReference)
    getStateParameters(pageRef) {
        if (pageRef?.state?.c__recordId) {
            this.recordId = pageRef.state.c__recordId;
        }
    }
}