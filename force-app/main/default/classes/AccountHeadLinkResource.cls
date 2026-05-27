@RestResource(urlMapping='/AccountHeadLink/*')
global without sharing class AccountHeadLinkResource {

    @HttpPost
    global static void linkAccountHead() {

        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String rawBody = req.requestBody.toString();
            System.debug('Relationship payload >> ' + rawBody);

            Map<String, Object> rawMap =
                (Map<String, Object>) JSON.deserializeUntyped(rawBody);

            Boolean isFlatDelete = rawMap.containsKey('account_headrelationshipid')
                                && rawMap.get('is_delete') == true;

            if (isFlatDelete) {
                String relId = (String) rawMap.get('account_headrelationshipid');

                ChildResult r = new ChildResult();
                r.relationshipId = relId;

                if (String.isBlank(relId)) {
                    r.success = false;
                    r.message = 'account_headrelationshipid is required for delete.';
                    res.statusCode   = 400;
                    res.responseBody = Blob.valueOf(JSON.serialize(
                        new LinkResponse(false, 'account_headrelationshipid is required for delete.',
                                         new List<ChildResult>{ r })
                    ));
                    return;
                }

                r.success = true;
                r.message = 'Queued for deletion.';
                System.enqueueJob(
                    new DeleteAccountHeadRelationshipQueueable(
                        new List<String>{ relId.trim() }
                    )
                );

                res.statusCode   = 200;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new LinkResponse(true, 'Processed successfully.',
                                     new List<ChildResult>{ r })
                ));
                return;
            }

            // ── Standard link/delete payload ──────────────────────────────────
            LinkRequest payload =
                (LinkRequest) JSON.deserialize(rawBody, LinkRequest.class);

            // ── Basic structural validation ────────────────────────────────────
            if (payload.parent == null ||
                payload.children == null ||
                payload.children.isEmpty()) {

                res.statusCode   = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new LinkResponse(false, 'parent block and at least one child are required.', null)
                ));
                return;
            }

            if (String.isBlank(payload.parent.accountId)) {
                res.statusCode   = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new LinkResponse(false, 'parent accountId is required.', null)
                ));
                return;
            }

            // ── Separate DELETE vs LINK children ──────────────────────────────
            List<ChildRequest> deleteRequests = new List<ChildRequest>();
            List<ChildRequest> linkRequests   = new List<ChildRequest>();

            for (ChildRequest cr : payload.children) {
                if (cr.is_delete == true) {
                    deleteRequests.add(cr);
                } else {
                    linkRequests.add(cr);
                }
            }

            // ── Handle DELETE children ─────────────────────────────────────────
            List<ChildResult> deleteResults = new List<ChildResult>();

            if (!deleteRequests.isEmpty()) {
                List<String>      relationshipIds   = new List<String>();
                List<ChildResult> deleteValidErrors = new List<ChildResult>();

                for (ChildRequest cr : deleteRequests) {
                    ChildResult r = new ChildResult();
                    r.firstName = cr.firstName;
                    r.lastName  = cr.lastName;

                    if (String.isBlank(cr.account_headrelationshipid)) {
                        r.success = false;
                        r.message = 'account_headrelationshipid is required for delete.';
                        deleteValidErrors.add(r);
                    } else {
                        relationshipIds.add(cr.account_headrelationshipid.trim());
                        r.relationshipId = cr.account_headrelationshipid.trim();
                        r.success        = true;
                        r.message        = 'Queued for deletion.';
                        deleteResults.add(r);
                    }
                }

                deleteResults.addAll(deleteValidErrors);

                if (!relationshipIds.isEmpty()) {
                    System.enqueueJob(
                        new DeleteAccountHeadRelationshipQueueable(relationshipIds)
                    );
                }
            }

            // ── Handle LINK children ──────────────────────────────────────────
            List<ChildResult> linkResults = new List<ChildResult>();

            if (!linkRequests.isEmpty()) {

                // Field-level validation — only email and mobilePhone are required
                List<ChildResult> validationErrors = new List<ChildResult>();
                for (ChildRequest cr : linkRequests) {
                    if (String.isBlank(cr.email) ||
                        String.isBlank(cr.mobilePhone)) {

                        ChildResult r = new ChildResult();
                        r.firstName = cr.firstName;
                        r.lastName  = cr.lastName;
                        r.success   = false;
                        r.message   = 'email and mobilePhone are required.';
                        validationErrors.add(r);
                    }
                }

                if (!validationErrors.isEmpty()) {
                    res.statusCode   = 400;
                    res.responseBody = Blob.valueOf(JSON.serialize(
                        new LinkResponse(false, 'Child validation failed.', validationErrors)
                    ));
                    return;
                }

                // Fetch parent account
                List<Account> parentAccounts = [
                    SELECT Id, Name
                    FROM   Account
                    WHERE  Id              = :payload.parent.accountId
                    AND    IsPersonAccount = true
                    LIMIT  1
                ];

                if (parentAccounts.isEmpty()) {
                    res.statusCode   = 404;
                    res.responseBody = Blob.valueOf(JSON.serialize(
                        new LinkResponse(false, 'Parent Account not found.', null)
                    ));
                    return;
                }
                Account parentAccount = parentAccounts[0];

                Set<String> emails       = new Set<String>();
                Set<String> mobilePhones = new Set<String>();

                for (ChildRequest cr : linkRequests) {
                    emails.add(cr.email.trim().toLowerCase());
                    mobilePhones.add(normalizePhone(cr.mobilePhone));
                }

                Map<String, Account> emailToAccount = new Map<String, Account>();
                Map<String, Account> keyToAccount   = new Map<String, Account>();

                for (Account a : [
                    SELECT Id, Name, FirstName, LastName, PersonEmail, PersonMobilePhone
                    FROM   Account
                    WHERE  PersonEmail     IN :emails
                    AND    IsPersonAccount = true
                ]) {
                    if (String.isBlank(a.PersonEmail)) continue;

                    emailToAccount.put(a.PersonEmail.trim().toLowerCase(), a);

                    if (String.isBlank(a.PersonMobilePhone)) continue;

                    String key = buildKey(a.FirstName, a.LastName, a.PersonEmail, normalizePhone(a.PersonMobilePhone));
                    keyToAccount.put(key, a);
                }

                Set<Id> matchedChildIds = new Set<Id>();
                for (Account a : keyToAccount.values()) {
                    matchedChildIds.add(a.Id);
                }

                Map<Id, Account_Head_Relationship__c> existingJunctionMap =
                    new Map<Id, Account_Head_Relationship__c>();

                if (!matchedChildIds.isEmpty()) {
                    for (Account_Head_Relationship__c jr : [
                        SELECT Id, Authorized_Account_Access__c
                        FROM   Account_Head_Relationship__c
                        WHERE  Member_Account__c            = :parentAccount.Id
                        AND    Authorized_Account_Access__c IN :matchedChildIds
                    ]) {
                        existingJunctionMap.put(jr.Authorized_Account_Access__c, jr);
                    }
                }

                List<Account_Head_Relationship__c> toInsert       = new List<Account_Head_Relationship__c>();
                Map<Id, ChildResult>               pendingResults = new Map<Id, ChildResult>();

                for (ChildRequest cr : linkRequests) {

                    ChildResult result = new ChildResult();
                    result.firstName  = cr.firstName;
                    result.lastName   = cr.lastName;

                    String key             = buildKey(cr.firstName, cr.lastName, cr.email.trim(), normalizePhone(cr.mobilePhone));
                    String normalizedEmail = cr.email.trim().toLowerCase();

                    if (!keyToAccount.containsKey(key)) {
                        result.success = false;

                        if (!emailToAccount.containsKey(normalizedEmail)) {
                            result.message = 'Member not found with the provided email address and Phone Number.';
                        } else {
                            result.message = 'Mobile phone number does not match. Please verify the mobile number and try again.';
                        }

                        linkResults.add(result);
                        continue;
                    }

                    Account childAccount  = keyToAccount.get(key);
                    Id      childId       = childAccount.Id;
                    result.childAccountId = String.valueOf(childId);

                    if (childId == parentAccount.Id) {
                        result.success = false;
                        result.message = 'Parent and Child cannot be the same Account.';
                        linkResults.add(result);
                        continue;
                    }

                    // Already linked
                    if (existingJunctionMap.containsKey(childId)) {
                        result.success        = true;
                        result.message        = 'Relationship already exists.';
                        result.relationshipId = existingJunctionMap.get(childId).Id;
                        linkResults.add(result);
                        continue;
                    }

                    Account_Head_Relationship__c junction = new Account_Head_Relationship__c(
                        Member_Account__c            = parentAccount.Id,
                        Authorized_Account_Access__c = childId,
                        Relationship__c              = String.isNotBlank(cr.relationship)  ? cr.relationship  : null,
                        Portal_Access_Status__c      = String.isNotBlank(cr.portal_status) ? cr.portal_status : null,
                        Give_Access__c               = cr.give_access   != null ? cr.give_access   : false,
                        Request_Access__c            = cr.request_access != null ? cr.request_access : false
                    );

                    toInsert.add(junction);
                    pendingResults.put(childId, result);
                }

                if (!toInsert.isEmpty()) {
                    insert toInsert;
                    for (Account_Head_Relationship__c j : toInsert) {
                        ChildResult r = pendingResults.get(j.Authorized_Account_Access__c);
                        if (r != null) {
                            r.success        = true;
                            r.message        = 'Account Head Relationship created successfully.';
                            r.relationshipId = j.Id;
                            r.give_access    = j.Give_Access__c;    
                            r.request_access = j.Request_Access__c;
                            linkResults.add(r);
                        }
                    }
                }
            }

            // ── Merge all results and respond ─────────────────────────────────
            List<ChildResult> allResults = new List<ChildResult>();
            allResults.addAll(linkResults);
            allResults.addAll(deleteResults);

            res.statusCode   = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new LinkResponse(true, 'Processed successfully.', allResults)
            ));

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'AccountHeadLinkResource error: ' + ex.getMessage());
            res.statusCode   = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new LinkResponse(false, 'Internal Server Error: ' + ex.getMessage(), null)
            ));
        }
    }

    // ── Builds a match key using email + phone only ───────────────────────────
    private static String buildKey(String fn, String ln, String em, String mob) {
        return (em.trim().toLowerCase() + '|' + normalizePhone(mob)).toLowerCase();
    }

    private static String stripSpaces(String name) {
        if (String.isBlank(name)) return '';
        return name.replaceAll('\\s+', '');
    }

    private static String normalizePhone(String phone) {
        if (String.isBlank(phone)) return '';
        return phone.replaceAll('[^0-9]', '');
    }

    private static String normalizeName(String name) {
        if (String.isBlank(name)) return '';
        return name.trim().replaceAll('\\s+', ' ');
    }

    // ── Wrapper Classes ───────────────────────────────────────────────────────
    global class ParentRequest {
        global String  accountId;
        global String  first_name;
        global String  last_name;
        global String  id;
        global Boolean is_head;
    }

    global class ChildRequest {
        global String  account_headrelationshipid;
        global String  firstName;
        global String  lastName;
        global String  email;
        global String  mobilePhone;
        global String  relationship;
        global String  portal_status;
        global String  headAccountName;
        global Boolean is_delete;
        global Boolean give_access;    
        global Boolean request_access;
    }

    global class LinkRequest {
        global ParentRequest      parent;
        global List<ChildRequest> children;
    }

    global class ChildResult {
        global String  firstName;
        global String  lastName;
        global String  childAccountId;
        global Boolean success;
        global String  message;
        global String  relationshipId;
        global Boolean give_access;
        global Boolean request_access;
    }

    global class LinkResponse {
        global Boolean           success;
        global String            message;
        global List<ChildResult> results;

        global LinkResponse(Boolean s, String m, List<ChildResult> r) {
            success = s;
            message = m;
            results = r;
        }
    }
}