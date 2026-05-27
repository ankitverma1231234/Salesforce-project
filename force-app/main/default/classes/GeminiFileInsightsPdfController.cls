public with sharing class GeminiFileInsightsPdfController {

    public class SectionRow {
        public String label { get; set; }
        public String html { get; set; }
    }

    public class KeyFieldRow {
        public String groupName { get; set; }
        public String label { get; set; }
        public String value { get; set; }
    }

    public String fileTitle        { get; private set; }
    public String generatedOn      { get; private set; }
    public String summaryHtml      { get; private set; }
    public String keyFindingsHtml  { get; private set; }
    public List<SectionRow>  otherSections { get; private set; }
    public List<KeyFieldRow> keyFields     { get; private set; }

    // Patient / Account demographics
    public String  patientName         { get; private set; }
    public String  patientDob          { get; private set; }
    public String  patientPhone        { get; private set; }
    public String  patientEmail        { get; private set; }
    public String  patientAddress      { get; private set; }
    public String  patientBiologicalSex{ get; private set; }
    public String  patientMaidenName   { get; private set; }
    public Boolean hasPatientData      { get; private set; }

    // Document-level metadata surfaced from AI-extracted keyFields (no hardcoded values).
    public String  consultingClinician { get; private set; }
    public String  documentLocation    { get; private set; }

    public Boolean getHasConsultingClinician() { return String.isNotBlank(consultingClinician); }
    public Boolean getHasDocumentLocation()    { return String.isNotBlank(documentLocation); }

    public Boolean getHasData() {
        return String.isNotBlank(summaryHtml)
            || String.isNotBlank(keyFindingsHtml)
            || (otherSections != null && !otherSections.isEmpty())
            || (keyFields     != null && !keyFields.isEmpty());
    }

    public Boolean getHasKeyFields() {
        return keyFields != null && !keyFields.isEmpty();
    }

    public Boolean getHasSummary() {
        return String.isNotBlank(summaryHtml);
    }

    public Boolean getHasKeyFindings() {
        return String.isNotBlank(keyFindingsHtml);
    }

    public Boolean getHasOtherSections() {
        return otherSections != null && !otherSections.isEmpty();
    }

    public GeminiFileInsightsPdfController() {
        otherSections = new List<SectionRow>();
        keyFields     = new List<KeyFieldRow>();
        hasPatientData = false;
        generatedOn    = Datetime.now().format('MM/dd/yyyy hh:mm a');

        // Bulletproof primary path: read the analysis JSON from a specific Attachment by Id.
        // The caller writes this Attachment and passes its Id as a URL param BEFORE
        // invoking getContentAsPDF(), so this lookup is immune to platform-cache state,
        // cross-context static-state loss, and any title/parent re-derivation drift.
        String contentDocumentId = ApexPages.currentPage().getParameters().get('contentDocumentId');
        String analysisAttachmentId = ApexPages.currentPage().getParameters().get('analysisAttachmentId');
        String cached;

        if (String.isNotBlank(analysisAttachmentId)) {
            List<Attachment> atts = [
                SELECT Body FROM Attachment WHERE Id = :analysisAttachmentId LIMIT 1
            ];
            if (!atts.isEmpty() && atts[0].Body != null) {
                cached = atts[0].Body.toString();
            }
        }

        // Legacy fallback: derive Attachment from contentDocumentId via the note service.
        // Kept so any caller that hasn't been updated still renders correctly.
        if (String.isBlank(cached) && String.isNotBlank(contentDocumentId)) {
            GeminiFileInsightsController.AnalysisBundleWrapper noteBundle =
                GeminiAnalysisNoteService.getStoredAnalysis((Id) contentDocumentId);
            if (noteBundle != null) {
                cached = JSON.serialize(noteBundle);
            }
        }

        if (String.isBlank(cached)) {
            fileTitle = 'AI Summary';
            return;
        }

        GeminiFileInsightsController.AnalysisBundleWrapper bundle =
            (GeminiFileInsightsController.AnalysisBundleWrapper)
            JSON.deserialize(cached, GeminiFileInsightsController.AnalysisBundleWrapper.class);

        fileTitle = String.isNotBlank(bundle.analysisTitle)
            ? bundle.analysisTitle
            : 'AI Summary';

        // Parse generatedOn from ISO string if available
        if (String.isNotBlank(bundle.generatedOn)) {
            try {
                String isoStr = bundle.generatedOn.replace('T', ' ').replace('Z', '');
                Datetime dt = Datetime.valueOfGmt(isoStr);
                generatedOn = dt.format('MM/dd/yyyy hh:mm a');
            } catch (Exception e) {
                // keep default
            }
        }

        Map<String, String> sectionLabels = new Map<String, String>{
            'summary'              => 'Summary',
            'keyFindings'          => 'Key Findings',
            'medicationReview'     => 'Medication Review',
            'labVitals'            => 'Lab & Vitals',
            'riskAssessment'       => 'Risk Assessment',
            'actionItems'          => 'Action Items',
            'patientSummary'       => 'Patient Summary',
            // Extended clinical sections (render only when AI returns non-blank content)
            'chiefComplaint'       => 'Chief Complaint',
            'keySymptoms'          => 'Key Symptoms',
            'allergies'            => 'Allergies',
            'currentMedications'   => 'Current Medications',
            'medicalHistory'       => 'Medical History / Problems',
            'surgicalHistory'      => 'Surgical History',
            'familyHistory'        => 'Family History',
            'socialHistory'        => 'Social History',
            'physicalExam'         => 'Physical Exam',
            'labs'                 => 'Labs',
            'imaging'              => 'Imaging',
            'assessment'           => 'Assessment',
            'differentialDiagnoses'=> 'Differential Diagnoses',
            'treatmentPlan'        => 'Treatment Plan'
        };

        List<String> orderedKeys = new List<String>{
            'summary', 'keyFindings',
            'chiefComplaint', 'keySymptoms', 'allergies', 'currentMedications',
            'medicalHistory', 'surgicalHistory', 'familyHistory', 'socialHistory',
            'physicalExam', 'labs', 'imaging',
            'assessment', 'differentialDiagnoses', 'treatmentPlan',
            'medicationReview', 'labVitals', 'riskAssessment', 'actionItems', 'patientSummary'
        };

        if (bundle.sections != null) {
            for (String keyName : orderedKeys) {
                if (!bundle.sections.containsKey(keyName)) continue;

                String html = bundle.sections.get(keyName);
                if (String.isBlank(html)) continue;

                String stripped = html.replaceAll('<[^>]*>', '').trim().toLowerCase();
                if (stripped == 'no information available for this section.'
                    || stripped == 'no information available.'
                    || stripped == 'not documented.'
                    || stripped == 'n/a'
                    || stripped == '-'
                    || String.isBlank(stripped)) {
                    continue;
                }

                String sanitized = sanitizeHtml(html);

                if (keyName == 'summary') {
                    summaryHtml = sanitized;
                } else if (keyName == 'keyFindings') {
                    keyFindingsHtml = sanitized;
                } else {
                    SectionRow row = new SectionRow();
                    row.label = sectionLabels.get(keyName);
                    row.html  = sanitized;
                    otherSections.add(row);
                }
            }
        }

        if (bundle.keyFields != null) {
            for (GeminiFileInsightsController.KeyFieldWrapper fieldRow : bundle.keyFields) {
                if (String.isBlank(fieldRow.value)
                    || fieldRow.value.trim() == '-'
                    || fieldRow.value.trim() == 'Not stated') {
                    continue;
                }
                KeyFieldRow row = new KeyFieldRow();
                row.groupName = fieldRow.groupName;
                row.label     = fieldRow.label;
                row.value     = fieldRow.value;
                keyFields.add(row);

                // Opportunistically surface clinician / location for the header strip.
                String labelNorm = String.isNotBlank(fieldRow.label) ? fieldRow.label.trim().toLowerCase() : '';
                if (String.isBlank(consultingClinician)
                    && (labelNorm == 'consulting clinician' || labelNorm == 'clinician' || labelNorm == 'provider')) {
                    consultingClinician = fieldRow.value;
                }
                if (String.isBlank(documentLocation)
                    && (labelNorm == 'location' || labelNorm == 'facility')) {
                    documentLocation = fieldRow.value;
                }
            }
        }

        // Load patient data from the linked Account
        if (String.isNotBlank(bundle.parentRecordId)) {
            try {
                Id parentId = (Id) bundle.parentRecordId;
                if (parentId.getSObjectType() == Account.SObjectType) {
                    List<Account> accounts = [
                        SELECT Name,
                               Date_of_Birth__pc,
                               PersonMobilePhone,
                               PersonEmail,
                               PersonMailingStreet,
                               PersonMailingCity,
                               PersonMailingState,
                               PersonMailingPostalCode,
                               Maiden_Name__pc,
                               Biological_Sex_at_Birth__c
                        FROM Account
                        WHERE Id = :parentId
                        LIMIT 1
                    ];

                    if (!accounts.isEmpty()) {
                        Account acc = accounts[0];

                        patientName  = acc.Name;
                        patientPhone = acc.PersonMobilePhone;
                        patientEmail = acc.PersonEmail;
                        patientMaidenName = String.isNotBlank(acc.Maiden_Name__pc)
                            ? acc.Maiden_Name__pc : null;

                        if (acc.Date_of_Birth__pc != null) {
                            patientDob = Datetime.newInstance(
                                acc.Date_of_Birth__pc.year(),
                                acc.Date_of_Birth__pc.month(),
                                acc.Date_of_Birth__pc.day()
                            ).format('MM/dd/yyyy');
                        }

                        List<String> addrParts = new List<String>();
                        if (String.isNotBlank(acc.PersonMailingStreet))     addrParts.add(acc.PersonMailingStreet);
                        if (String.isNotBlank(acc.PersonMailingCity))       addrParts.add(acc.PersonMailingCity);
                        if (String.isNotBlank(acc.PersonMailingState))      addrParts.add(acc.PersonMailingState);
                        if (String.isNotBlank(acc.PersonMailingPostalCode)) addrParts.add(acc.PersonMailingPostalCode);
                        if (!addrParts.isEmpty()) {
                            patientAddress = String.join(addrParts, ', ');
                        }

                        String sex = acc.Biological_Sex_at_Birth__c;
                        if (String.isNotBlank(sex)) {
                           
                            patientBiologicalSex = sex ;
                        }

                        hasPatientData = true;
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Could not load patient data for PDF: ' + e.getMessage());
            }
        }

        // When Account demographics are shown, drop the AI "Patient Summary"
        // section to avoid duplicating Name / DOB / Biological Sex / Phone etc.
        if (hasPatientData && !otherSections.isEmpty()) {
            List<SectionRow> filtered = new List<SectionRow>();
            for (SectionRow s : otherSections) {
                if (s.label != 'Patient Summary') {
                    filtered.add(s);
                }
            }
            otherSections = filtered;
        }
    }

    private static String sanitizeHtml(String html) {
        if (String.isBlank(html)) return '';
        String cleaned = html;
        cleaned = cleaned.replaceAll('(?is)<script.*?>.*?</script>', '');
        cleaned = cleaned.replaceAll('(?is)<style.*?>.*?</style>', '');
        cleaned = cleaned.replaceAll('(?i)javascript:', '');
        cleaned = cleaned.replaceAll('(?i)on\\w+\\s*=\\s*"[^"]*"', '');
        cleaned = cleaned.replaceAll('(?i)on\\w+\\s*=\\s*\'[^\']*\'', '');
        return cleaned;
    }
}