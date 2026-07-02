public with sharing class MedicationStatementController {


    @AuraEnabled
    public static Id createMedicationStatement(
        String medicationName,
        Id patientId,
        String dose,
        String frequency,
        String reason,
        String status,
        Datetime startDateTime,
        String internalComments
    ){

        //Create Medication
        Medication med = new Medication();
        med.Name = medicationName;
        insert med;


        //Create Medication Statement
        MedicationStatement ms = new MedicationStatement();

        ms.MedicationId = med.Id;
        ms.PatientId = patientId;

        ms.Dose__c = dose;
        ms.Frequency__c = frequency;
        ms.Reason__c = reason;

        ms.Status = status;

        ms.StartDateTime = startDateTime;

        ms.Comments__c = internalComments;


        insert ms;


        return ms.Id;
    }
}