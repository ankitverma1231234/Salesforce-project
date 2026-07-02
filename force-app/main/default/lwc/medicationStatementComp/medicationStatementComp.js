import { LightningElement, api } from 'lwc';


import createMedicationStatement
from '@salesforce/apex/MedicationStatementController.createMedicationStatement';


import { NavigationMixin } 
from 'lightning/navigation';



export default class MedicationStatementCreate 
extends NavigationMixin(LightningElement){


@api recordId;


//Account Id comes automatically
//from Related List New button


medicationName;

dose;

frequency;

reason;

status;


startDateTime;


comments;



statusOptions=[

{
label:'Active',
value:'Active'
},

{
label:'Completed',
value:'Completed'
}

];




handleMedication(event){

this.medicationName =
event.target.value;

}



handleChange(event){

this[event.target.dataset.name] =
event.target.value;

}




handleStatus(event){

this.status =
event.detail.value;

}



handleDateTime(event){

this.startDateTime =
event.target.value;

}



handleComments(event){

this.comments =
event.target.value;

}




save(){


createMedicationStatement({


medicationName:this.medicationName,


patientId:this.recordId,


dose:this.dose,


frequency:this.frequency,


reason:this.reason,


status:this.status,


startDateTime:this.startDateTime,


internalComments:this.comments


})
.then(result=>{


this[NavigationMixin.Navigate]({

type:'standard__recordPage',

attributes:{

recordId:result,

objectApiName:'MedicationStatement',

actionName:'view'

}

});


});


}




cancel(){

window.history.back();

}



}