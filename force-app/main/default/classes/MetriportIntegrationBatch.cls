global class MetriportIntegrationBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
    
    private Map<String, List<SObject>> recordsMap;
    private DateTime startTime;
    private DateTime endTime;
    private String metriportUserId;
    
    global void execute(SchedulableContext sc) {
        MetriportIntegrationBatch batch = new MetriportIntegrationBatch();
        Database.executeBatch(batch, 200);
    }
    private String getOrgWideEmailAddressId() {
    List<OrgWideEmailAddress> owaList = [
        SELECT Id 
        FROM OrgWideEmailAddress 
        WHERE Address = 'support@batoncare.com'
        LIMIT 1
    ];
    
    if (owaList.isEmpty()) {
        System.debug('MetriportIntegrationBatch: Org Wide Email Address support@batoncare.com not found. ' +
                     'Falling back to default sender.');
        return null;
    }
    return owaList[0].Id;
}
    
    // ── Original default constructor (unchanged behavior) ─────────────────────
    global MetriportIntegrationBatch() {
        recordsMap = new Map<String, List<SObject>>();
        Date today = Date.today();
        startTime = DateTime.newInstance(today, Time.newInstance(3, 0, 0, 0));
        endTime   = DateTime.newInstance(today, Time.newInstance(3, 30, 0, 0));
        
        List<User> metriportUsers = [
            SELECT Id FROM User 
            WHERE Name = 'Metriport Integration Site Guest User' 
            LIMIT 1
        ];
        metriportUserId = metriportUsers.isEmpty() ? null : metriportUsers[0].Id;
    }

    // ── Testable constructor – allows tests to inject time window & user ID ───
    @TestVisible
    private MetriportIntegrationBatch(DateTime customStart, DateTime customEnd, String customUserId) {
        recordsMap      = new Map<String, List<SObject>>();
        startTime       = customStart;
        endTime         = customEnd;
        metriportUserId = customUserId;
    }
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id FROM AllergyIntolerance
            WHERE CreatedDate >= :startTime
            AND   CreatedDate <= :endTime
            AND   CreatedById  = :metriportUserId
            LIMIT 1
        ]);
    }
    
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (metriportUserId == null) return;
        
        // ── 1. Allergy ────────────────────────────────────────────────────────
        List<AllergyIntolerance> allergies = [
            SELECT Name, Combine_allergy_and_Generic__c, Patient.Name
            FROM   AllergyIntolerance
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!allergies.isEmpty()) recordsMap.put('Allergy', allergies);
        
        // ── 2. Medication Statement ───────────────────────────────────────────
        List<MedicationStatement> medStatements = [
            SELECT Name, Medication_Name__c, Patient.Name
            FROM   MedicationStatement
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!medStatements.isEmpty()) recordsMap.put('Medication Statement', medStatements);
        
        // ── 3. Medication Administration ──────────────────────────────────────
        List<MedicationAdministration> medAdmins = [
            SELECT Name, Medication.Name, Patient.Name
            FROM   MedicationAdministration
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!medAdmins.isEmpty()) recordsMap.put('Medication Administration', medAdmins);
        
        // ── 4. Medication Request ─────────────────────────────────────────────
        List<MedicationRequest> medRequests = [
            SELECT Name, Medication.Name, Patient.Name
            FROM   MedicationRequest
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!medRequests.isEmpty()) recordsMap.put('Medication Request', medRequests);
        
        // ── 5. Medication Dispense ────────────────────────────────────────────
        List<MedicationDispense> medDispenses = [
            SELECT Name, Medication.Name, Patient.Name
            FROM   MedicationDispense
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!medDispenses.isEmpty()) recordsMap.put('Medication Dispense', medDispenses);
        
        // ── 6. Medical History ────────────────────────────────────────────────
        List<HealthCondition> healthConditions = [
            SELECT Name, Patient.Name, ProblemName
            FROM   HealthCondition
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!healthConditions.isEmpty()) recordsMap.put('Medical History', healthConditions);
        
        // ── 7. Surgical History ───────────────────────────────────────────────
        List<HealthcareProcedure> surgicalHistories = [
            SELECT Name, Patient__r.Name
            FROM   HealthcareProcedure
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!surgicalHistories.isEmpty()) recordsMap.put('Surgical History', surgicalHistories);
        
        // ── 8. Encounter ──────────────────────────────────────────────────────
        List<Visit> encounters = [
            SELECT Name, Visit_Name__c
            FROM   Visit
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!encounters.isEmpty()) recordsMap.put('Encounter', encounters);
        
        // ── 9. Labs (CareObservation – category = Laboratory) ─────────────────
        List<CareObservation> labs = [
            SELECT Name, ObservedSubject.Name
            FROM   CareObservation
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
            AND    Category   = 'Laboratory'
        ];
        if (!labs.isEmpty()) recordsMap.put('Labs', labs);
        
        // ── 10. Diagnostic Summary ────────────────────────────────────────────
        List<DiagnosticSummary> diagSummaries = [
            SELECT Name, Patient.Name, Summary
            FROM   DiagnosticSummary
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!diagSummaries.isEmpty()) recordsMap.put('Diagnostic Summary', diagSummaries);
        
        // ── 11. Immunization ──────────────────────────────────────────────────
        List<PatientImmunization> immunizations = [
            SELECT Name, Vaccine_Name__c, Patient.Name
            FROM   PatientImmunization
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!immunizations.isEmpty()) recordsMap.put('Immunization', immunizations);
        
        // ── 12. Vitals (CareObservation – category = Vital-Signs) ─────────────
        List<CareObservation> vitals = [
            SELECT Name, ObservedSubject.Name
            FROM   CareObservation
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
            AND    Category   = 'Vital-Signs'
        ];
        if (!vitals.isEmpty()) recordsMap.put('Vitals', vitals);
        
        // ── 13. Social History (CareObservation – category = Social-History) ──
        List<CareObservation> socialHistory = [
            SELECT Name, ObservedSubject.Name
            FROM   CareObservation
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
            AND    Category   = 'Social-History'
        ];
        if (!socialHistory.isEmpty()) recordsMap.put('Social History', socialHistory);
        
        // ── 14. Family Member History ─────────────────────────────────────────
        List<Family_Member_History__c> familyHistories = [
            SELECT Name, Patient__r.Name
            FROM   Family_Member_History__c
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!familyHistories.isEmpty()) recordsMap.put('Family Member History', familyHistories);
        
        // ── 15. Related Person ────────────────────────────────────────────────
        List<Contact> relatedPersons = [
            SELECT Name, Account__r.Name
            FROM   Contact
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!relatedPersons.isEmpty()) recordsMap.put('Related Person', relatedPersons);
        
        // ── 16. Clinical Service Request ──────────────────────────────────────
        List<ClinicalServiceRequest> clinicalRequests = [
            SELECT Name, Patient.Name
            FROM   ClinicalServiceRequest
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!clinicalRequests.isEmpty()) recordsMap.put('Clinical Service Request', clinicalRequests);
        
        // ── 17. Healthcare Professional ───────────────────────────────────────
        List<HealthcarePractitionerFacility> hcProfessionals = [
            SELECT Name, Account.Name
            FROM   HealthcarePractitionerFacility
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!hcProfessionals.isEmpty()) recordsMap.put('Healthcare Professional', hcProfessionals);
        
        // ── 18. Healthcare Facility ───────────────────────────────────────────
        List<HealthcareFacility> hcFacilities = [
            SELECT Name, Account.Name
            FROM   HealthcareFacility
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!hcFacilities.isEmpty()) recordsMap.put('Healthcare Facility', hcFacilities);
        
    
        
        
        // ── 20. File ──────────────────────────────────────────────────────────
        List<ContentVersion> files = [
            SELECT Title
            FROM   ContentVersion
            WHERE  CreatedDate  >= :startTime
            AND    CreatedDate  <= :endTime
            AND    CreatedById   = :metriportUserId
        ];
        if (!files.isEmpty()) recordsMap.put('File', files);
    }
    
    global void finish(Database.BatchableContext bc) {
        List<String> toAddresses = getEmailRecipientsFromCustomSetting();
        
        if (toAddresses.isEmpty()) {
            System.debug('MetriportIntegrationBatch: No email recipients configured in ' +
                         'Metriport_Daily_Email__c custom setting. Skipping email.');
            return;
        }
        
        Integer totalCount = 0;
        for (List<SObject> recs : recordsMap.values()) {
            totalCount += recs.size();
        }
        
        String htmlBody = recordsMap.isEmpty() ? buildNoRecordsBody() : buildEmailBody();
        sendEmail(htmlBody, totalCount, toAddresses);
    }
    
    // ── Custom Setting Email Resolver ─────────────────────────────────────────
    
    /**
     * Reads all records from the Metriport_Daily_Email__c list custom setting,
     * splits each Email__c value on commas/semicolons (in case multiple addresses
     * are stored in one record), trims whitespace, and returns a de-duplicated list.
     */
    private List<String> getEmailRecipientsFromCustomSetting() {
        List<String> addresses = new List<String>();
        Set<String>  seen      = new Set<String>();
        
        // List Custom Setting – fetch all configured records
        Map<String, Metriport_Daily_Email__c> allSettings =
            Metriport_Daily_Email__c.getAll();
        
        if (allSettings == null || allSettings.isEmpty()) {
            System.debug('MetriportIntegrationBatch: Metriport_Daily_Email__c has no records.');
            return addresses;
        }
        
        for (Metriport_Daily_Email__c setting : allSettings.values()) {
            if (String.isBlank(setting.Email__c)) continue;
            
            // Support comma- or semicolon-separated addresses in a single field value
            List<String> parts = setting.Email__c.replaceAll(';', ',').split(',');
            for (String part : parts) {
                String email = part.trim();
                if (String.isNotBlank(email) && !seen.contains(email)) {
                    seen.add(email);
                    addresses.add(email);
                }
            }
        }
        
        return addresses;
    }
    
    // ── Email helpers ─────────────────────────────────────────────────────────
    
private void sendEmail(String htmlBody, Integer totalCount, List<String> toAddresses) {
    String owaId = getOrgWideEmailAddressId();
    
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(toAddresses);
    mail.setSubject('Metriport Daily Sync Report – ' + Date.today().format()
                   + ' | Total Records: ' + totalCount);
    mail.setHtmlBody(htmlBody);
    mail.setSaveAsActivity(false);
    
    if (owaId != null) {
        mail.setOrgWideEmailAddressId(owaId);
    }
    
    try {
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    } catch (Exception e) {
        System.debug('MetriportIntegrationBatch: Failed to send email. Error: ' + e.getMessage());
    }
}
    
    private String buildEmailBody() {
        String timeRange = startTime.format('hh:mm a') + ' – ' + endTime.format('hh:mm a');
        String dateStr   = Date.today().format();
        
        String html = '<html><body style="font-family:Arial,sans-serif;font-size:13px;color:#333;">';
        html += '<h2 style="color:#0070d2;">Metriport Integration – Daily Sync Report</h2>';
        html += '<p><strong>Date:</strong> '        + dateStr   + '</p>';
        html += '<p><strong>Time Window:</strong> ' + timeRange + '</p>';
        html += '<p><strong>Created By:</strong> Metriport </p><hr/>';
        
        Map<String, List<String>> sectionConfig = buildSectionConfig();
        
        for (String label : sectionConfig.keySet()) {
            if (!recordsMap.containsKey(label)) continue;
            
            List<SObject> recs = recordsMap.get(label);
            List<String>  cols = sectionConfig.get(label);
            
            html += '<h3 style="color:#005fb2;margin-bottom:4px;">' + label
                  + ' <span style="font-size:12px;color:#666;">('
                  + recs.size() + ' record' + (recs.size() > 1 ? 's' : '') + ')</span></h3>';
            html += '<table border="1" cellpadding="6" cellspacing="0" '
                  + 'style="border-collapse:collapse;width:100%;margin-bottom:20px;">';
            
            // Header row
            html += '<tr style="background-color:#0070d2;color:#fff;">';
            for (String col : cols) {
                html += '<th style="text-align:left;padding:8px;">' + col + '</th>';
            }
            html += '</tr>';
            
            // Data rows
            Boolean alt = false;
            for (SObject rec : recs) {
                String rowBg = alt ? '#f4f6f9' : '#ffffff';
                html += '<tr style="background-color:' + rowBg + ';">';
                html += buildRow(label, rec);
                html += '</tr>';
                alt = !alt;
            }
            html += '</table>';
        }
        
        html += '<hr/><p style="font-size:11px;color:#999;">This is an automated report generated '
              + 'at 4:00 AM. Please do not reply to this email.</p>';
        html += '</body></html>';
        return html;
    }
    
    private String buildNoRecordsBody() {
        String timeRange = startTime.format('hh:mm a') + ' – ' + endTime.format('hh:mm a');
        return '<html><body style="font-family:Arial,sans-serif;">'
             + '<h2 style="color:#0070d2;">Metriport Integration – Daily Sync Report</h2>'
             + '<p>No records were created ' + timeRange + ' today by '
             + 'Metriport.</p>'
             + '</body></html>';
    }
    
    private String buildRow(String label, SObject rec) {
        String row = '';
        if (label == 'Allergy') {
            AllergyIntolerance r = (AllergyIntolerance) rec;
            row += td(r.Name) + td(r.Combine_allergy_and_Generic__c) + td(r.Patient.Name);
        } else if (label == 'Medication Statement') {
            MedicationStatement r = (MedicationStatement) rec;
            row += td(r.Name) + td(r.Medication_Name__c) + td(r.Patient.Name);
        } else if (label == 'Medication Administration') {
            MedicationAdministration r = (MedicationAdministration) rec;
            row += td(r.Name) + td(r.Medication.Name) + td(r.Patient.Name);
        } else if (label == 'Medication Request') {
            MedicationRequest r = (MedicationRequest) rec;
            row += td(r.Name) + td(r.Medication.Name) + td(r.Patient.Name);
        } else if (label == 'Medication Dispense') {
            MedicationDispense r = (MedicationDispense) rec;
            row += td(r.Name) + td(r.Medication.Name) + td(r.Patient.Name);
        } else if (label == 'Medical History') {
            HealthCondition r = (HealthCondition) rec;
            row += td(r.Name) + td(r.Patient.Name) + td(r.ProblemName);
        } else if (label == 'Surgical History') {
            HealthcareProcedure r = (HealthcareProcedure) rec;
            row += td(r.Name) + td(r.Patient__r.Name);
        } else if (label == 'Encounter') {
            Visit r = (Visit) rec;
            row += td(r.Name) + td(r.Visit_Name__c);
        } else if (label == 'Labs' || label == 'Vitals' || label == 'Social History') {
            CareObservation r = (CareObservation) rec;
            row += td(r.Name) + td(r.ObservedSubject.Name);
        } else if (label == 'Diagnostic Summary') {
            DiagnosticSummary r = (DiagnosticSummary) rec;
            row += td(r.Name) + td(r.Patient.Name) + td(r.Summary);
        } else if (label == 'Immunization') {
            PatientImmunization r = (PatientImmunization) rec;
            row += td(r.Name) + td(r.Vaccine_Name__c) + td(r.Patient.Name);
        } else if (label == 'Family Member History') {
            Family_Member_History__c r = (Family_Member_History__c) rec;
            row += td(r.Name) + td(r.Patient__r.Name);
        } else if (label == 'Related Person') {
            Contact r = (Contact) rec;
            row += td(r.Name) + td(r.Account__r.Name);
        } else if (label == 'Clinical Service Request') {
            ClinicalServiceRequest r = (ClinicalServiceRequest) rec;
            row += td(r.Name) + td(r.Patient.Name);
        } else if (label == 'Healthcare Professional') {
            HealthcarePractitionerFacility r = (HealthcarePractitionerFacility) rec;
            row += td(r.Name) + td(r.Account.Name);
        } else if (label == 'Healthcare Facility') {
            HealthcareFacility r = (HealthcareFacility) rec;
            row += td(r.Name) + td(r.Account.Name);
        } else if (label == 'File') {
            ContentVersion r = (ContentVersion) rec;
            row += td(r.Title);
        }
        return row;
    }
    
    private String td(String val) {
        return '<td style="padding:8px;">' + (String.isBlank(val) ? '—' : val) + '</td>';
    }
    
    private Map<String, List<String>> buildSectionConfig() {
        Map<String, List<String>> cfg = new Map<String, List<String>>();
        cfg.put('Allergy',                   new List<String>{'Name', 'Combine Allergy & Generic', 'Patient Name'});
        cfg.put('Medication Statement',      new List<String>{'Name', 'Medication Name', 'Patient Name'});
        cfg.put('Medication Administration', new List<String>{'Name', 'Medication Name', 'Patient Name'});
        cfg.put('Medication Request',        new List<String>{'Name', 'Medication Name', 'Patient Name'});
        cfg.put('Medication Dispense',       new List<String>{'Name', 'Medication Name', 'Patient Name'});
        cfg.put('Medical History',           new List<String>{'Name', 'Patient Name', 'Problem Name'});
        cfg.put('Surgical History',          new List<String>{'Name', 'Patient Name'});
        cfg.put('Encounter',                 new List<String>{'Name', 'Visit Name'});
        cfg.put('Labs',                      new List<String>{'Name', 'Observed Subject'});
        cfg.put('Diagnostic Summary',        new List<String>{'Name', 'Patient Name', 'Summary'});
        cfg.put('Immunization',              new List<String>{'Name', 'Vaccine Name', 'Patient Name'});
        cfg.put('Vitals',                    new List<String>{'Name', 'Observed Subject'});
        cfg.put('Social History',            new List<String>{'Name', 'Observed Subject'});
        cfg.put('Family Member History',     new List<String>{'Name', 'Patient Name'});
        cfg.put('Related Person',            new List<String>{'Name', 'Account Name'});
        cfg.put('Clinical Service Request',  new List<String>{'Name', 'Patient Name'});
        cfg.put('Healthcare Professional',   new List<String>{'Name', 'Account Name'});
        cfg.put('Healthcare Facility',       new List<String>{'Name', 'Account Name'});
        cfg.put('File',                      new List<String>{'Title'});
        return cfg;
    }
}