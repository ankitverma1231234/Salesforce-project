@IsTest
public class ContactMedicalDataWrappersTest {

    @IsTest
    static void testWrappersInstantiation() {
        // ------------------------------
        // Create Address Wrappers
        // ------------------------------
        ContactMedicalDataWrappers.AddressData addr = new ContactMedicalDataWrappers.AddressData();
        addr.street = '123 Main St';
        addr.city = 'Metropolis';
        addr.state = 'NY';
        addr.postalCode = '10001';
        addr.country = 'USA';

        ContactMedicalDataWrappers.OtherAddressData otherAddr = new ContactMedicalDataWrappers.OtherAddressData();
        otherAddr.street = '456 Side St';
        otherAddr.city = 'Gotham';
        otherAddr.state = 'NJ';
        otherAddr.postalCode = '07001';
        otherAddr.country = 'USA';

        // ------------------------------
        // Create RecordCount Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.RecordCount rc = new ContactMedicalDataWrappers.RecordCount();
        rc.surgeries = 1;
        rc.medicalHistory = 2;
        rc.allergies = 3;
        rc.medications = 4;
        rc.insurancePlans = 5;
        rc.healthcareFacilitiesCount = 6;
        rc.HealthcareProfessionalCount = 7;
        rc.personalContactsCount = 8;
        rc.messageCaseCount = 9;
        rc.documentsCount = 10;

        // ------------------------------
        // Create SurgeryData Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.SurgeryData surgery = new ContactMedicalDataWrappers.SurgeryData();
        surgery.Id = 'S1';
        surgery.name = 'Appendectomy';
        surgery.Patient = 'John Doe';
        surgery.Surgery_Date = Date.today();

        // ------------------------------
        // Create MedicalHistoryData Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.MedicalHistoryData medHist = new ContactMedicalDataWrappers.MedicalHistoryData();
        medHist.Id = 'MH1';
        medHist.name = 'Diabetes';
        medHist.Medical_Problem = 'Type 2 Diabetes';

        // ------------------------------
        // Create AllergyData Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.AllergyData allergy = new ContactMedicalDataWrappers.AllergyData();
        allergy.Id = 'A1';
        allergy.Name = 'Peanuts';
        allergy.Severity = 'High';
        allergy.Reaction = 'Anaphylaxis';

        // ------------------------------
        // Create MedicationData Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.MedicationData medData = new ContactMedicalDataWrappers.MedicationData();
        medData.Id = 'M1';
        medData.medication = 'Metformin';
        medData.Dose = '500mg';

        // ------------------------------
        // Create InsuranceData Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.InsuranceData insData = new ContactMedicalDataWrappers.InsuranceData();
        insData.id = 'I1';
        insData.providerName = 'HealthCo';
        insData.GroupNumber = 'G123';
        insData.memberNumber = 'M456';

        // ------------------------------
        // Create HealthcareFacility Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.HealthcareFacility facility = new ContactMedicalDataWrappers.HealthcareFacility();
        facility.Id = 'HF1';
        facility.PractitionerName = 'Dr. Strange';
        facility.address = new ContactMedicalDataWrappers.HealthcareFacilityaddress();
        facility.address.street = '100 Marvel St';

        // ------------------------------
        // Create HealthcareProfessionals Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.HealthcareProfessionals prof = new ContactMedicalDataWrappers.HealthcareProfessionals();
        prof.Id = 'HP1';
        prof.healthcareProfessionalName = 'Dr. Banner';
        prof.Specialty = 'Radiology';
        prof.address = new ContactMedicalDataWrappers.HealthcareProfessionalsaddress();
        prof.address.city = 'New York';

        // ------------------------------
        // Create PersonalContacts Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.PersonalContacts pContact = new ContactMedicalDataWrappers.PersonalContacts();
        pContact.Id = 'PC1';
        pContact.FirstName = 'Jane';
        pContact.LastName = 'Doe';
        pContact.MobilePhone = '1234567890';

        // ------------------------------
        // Create DocumentData Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.DocumentData doc = new ContactMedicalDataWrappers.DocumentData();
        doc.Id = 'D1';
        doc.Title = 'MedicalReport.pdf';
        doc.FileType = 'PDF';

        // ------------------------------
        // Create ContactData Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.ContactData contact = new ContactMedicalDataWrappers.ContactData();
        contact.contactId = 'C1';
        contact.firstName = 'John';
        contact.lastName = 'Doe';
        contact.email = 'john@example.com';
        contact.phone = '1234567890';
        contact.address = addr;
        contact.otheraddress = otherAddr;
        contact.surgeries = new List<ContactMedicalDataWrappers.SurgeryData>{surgery};
        contact.medicalHistory = new List<ContactMedicalDataWrappers.MedicalHistoryData>{medHist};
        contact.allergies = new List<ContactMedicalDataWrappers.AllergyData>{allergy};
        contact.medications = new List<ContactMedicalDataWrappers.MedicationData>{medData};
        contact.insurancePlans = new List<ContactMedicalDataWrappers.InsuranceData>{insData};
        contact.healthcareFacilities = new List<ContactMedicalDataWrappers.HealthcareFacility>{facility};
        contact.healthcareProfessionals = new List<ContactMedicalDataWrappers.HealthcareProfessionals>{prof};
        contact.personalContacts = new List<ContactMedicalDataWrappers.PersonalContacts>{pContact};
        contact.documents = new List<ContactMedicalDataWrappers.DocumentData>{doc};

        // ------------------------------
        // Create DebugInfo Wrapper
        // ------------------------------
        ContactMedicalDataWrappers.DebugInfo debug = new ContactMedicalDataWrappers.DebugInfo();
        debug.originalPhone = '1234567890';
        debug.trimmedPhone = '1234567890';
        debug.cleanedPhone = '1234567890';

        // ------------------------------
        // Create ResponseWrapper
        // ------------------------------
        ContactMedicalDataWrappers.ResponseWrapper response = new ContactMedicalDataWrappers.ResponseWrapper();
        response.success = true;
        response.message = 'Test successful';
        response.searchedEmail = 'search@example.com';
        response.searchedPhone = '0987654321';
        response.data = contact;
        response.recordCount = rc;
        response.debugInfo = debug;

        System.assertEquals(true, response.success);
        System.assertEquals('Test successful', response.message);
        System.assertEquals('John', response.data.firstName);
        System.assertEquals(1, response.recordCount.surgeries);
        System.assertEquals('Peanuts', response.data.allergies[0].Name);
        System.assertEquals('HealthCo', response.data.insurancePlans[0].providerName);
        System.assertEquals('Jane', response.data.personalContacts[0].FirstName);
        System.assertEquals('MedicalReport.pdf', response.data.documents[0].Title);
    }
}