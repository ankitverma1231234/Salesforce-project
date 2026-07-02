@RestResource(urlMapping='/AccountHeadLink/*')
global without sharing class AccountHeadLinkResource {
    
    @HttpPost
    global static void linkAccountHead() {
        
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        
        try {
            String rawBody = req.requestBody.toString();
            
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
            
            
            LinkRequest payload =
                (LinkRequest) JSON.deserialize(rawBody, LinkRequest.class);
            
            
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
                
                Map<String, Account_Head_Relationship__c> existingGiveMap    = new Map<String, Account_Head_Relationship__c>();
                Map<String, Account_Head_Relationship__c> existingRequestMap = new Map<String, Account_Head_Relationship__c>();
                
                if (!matchedChildIds.isEmpty()) {
                    for (Account_Head_Relationship__c jr : [
                        SELECT Id, Authorized_Account_Access__c, Give_Access__c, Request_Access__c
                        FROM   Account_Head_Relationship__c
                        WHERE  Member_Account__c            = :parentAccount.Id
                        AND    Authorized_Account_Access__c IN :matchedChildIds
                    ]) {
                        String childKey = String.valueOf(jr.Authorized_Account_Access__c);
                        if (jr.Give_Access__c == true) {
                            existingGiveMap.put(childKey, jr);
                        }
                        if (jr.Request_Access__c == true) {
                            existingRequestMap.put(childKey, jr);
                        }
                    }
                }
                
                
                List<Account_Head_Relationship__c> toInsert        = new List<Account_Head_Relationship__c>();
                Map<String, ChildResult>           pendingResults  = new Map<String, ChildResult>();
                
                for (ChildRequest cr : linkRequests) {
                    
                    String normalizedEmail = cr.email.trim().toLowerCase();
                    String key             = buildKey(cr.firstName, cr.lastName, normalizedEmail, normalizePhone(cr.mobilePhone));
                    
                    // ── Account lookup ────────────────────────────────────────
                    if (!keyToAccount.containsKey(key)) {
                        ChildResult result = new ChildResult();
                        result.firstName = cr.firstName;
                        result.lastName  = cr.lastName;
                        result.success   = false;
                        
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
                    String  childIdStr    = String.valueOf(childId);
                    
                    // ── Self-link guard ───────────────────────────────────────
                    if (childId == parentAccount.Id) {
                        ChildResult result = new ChildResult();
                        result.firstName      = cr.firstName;
                        result.lastName       = cr.lastName;
                        result.childAccountId = childIdStr;
                        result.success        = false;
                        result.message        = 'Parent and Child cannot be the same Account.';
                        linkResults.add(result);
                        continue;
                    }
                    
                    Boolean wantsGive    = (cr.give_access    == true);
                    Boolean wantsRequest = (cr.request_access == true);
                    
                    Boolean giveExists    = existingGiveMap.containsKey(childIdStr);
                    Boolean requestExists = existingRequestMap.containsKey(childIdStr);
                    
                    
                    if ((wantsGive && wantsRequest) && giveExists && requestExists) {
                        ChildResult result = new ChildResult();
                        result.firstName            = cr.firstName;
                        result.lastName             = cr.lastName;
                        result.childAccountId       = childIdStr;
                        result.success              = true;
                        result.message              = 'Relationship already exists.';
                        result.give_access_rel_id   = existingGiveMap.get(childIdStr).Id;
                        result.request_access_rel_id = existingRequestMap.get(childIdStr).Id;
                        linkResults.add(result);
                        continue;
                    }
                    
                    
                    if (wantsGive && !wantsRequest && giveExists) {
                        ChildResult result = new ChildResult();
                        result.firstName          = cr.firstName;
                        result.lastName           = cr.lastName;
                        result.childAccountId     = childIdStr;
                        result.success            = true;
                        result.message            = 'Relationship already exists.';
                        result.give_access_rel_id = existingGiveMap.get(childIdStr).Id;
                        linkResults.add(result);
                        continue;
                    }
                    
                    if (wantsRequest && !wantsGive && requestExists) {
                        ChildResult result = new ChildResult();
                        result.firstName             = cr.firstName;
                        result.lastName              = cr.lastName;
                        result.childAccountId        = childIdStr;
                        result.success               = true;
                        result.message               = 'Relationship already exists.';
                        result.request_access_rel_id = existingRequestMap.get(childIdStr).Id;
                        linkResults.add(result);
                        continue;
                    }
                    
                    
                    if (wantsGive && !giveExists) {
                        Account_Head_Relationship__c giveJunction = new Account_Head_Relationship__c(
                            Member_Account__c            = parentAccount.Id,
                            Authorized_Account_Access__c = childId,
                            Relationship__c              = String.isNotBlank(cr.relationship)  ? cr.relationship  : null,
                            Portal_Access_Status__c      = String.isNotBlank(cr.portal_status) ? cr.portal_status : null,
                            Give_Access__c               = true,
                            Request_Access__c            = false
                        );
                        toInsert.add(giveJunction);
                        
                        ChildResult result = new ChildResult();
                        result.firstName      = cr.firstName;
                        result.lastName       = cr.lastName;
                        result.childAccountId = childIdStr;
                        result.give_access    = true;
                        result.request_access = false;
                        pendingResults.put(childIdStr + '|give', result);
                    }
                    
                    
                    if (wantsRequest && !requestExists) {
                        Account_Head_Relationship__c requestJunction = new Account_Head_Relationship__c(
                            Member_Account__c            = parentAccount.Id,
                            Authorized_Account_Access__c = childId,
                            Relationship__c              = String.isNotBlank(cr.relationship)  ? cr.relationship  : null,
                            Portal_Access_Status__c      = String.isNotBlank(cr.portal_status) ? cr.portal_status : null,
                            Give_Access__c               = false,
                            Request_Access__c            = true
                        );
                        toInsert.add(requestJunction);
                        
                        ChildResult result = new ChildResult();
                        result.firstName      = cr.firstName;
                        result.lastName       = cr.lastName;
                        result.childAccountId = childIdStr;
                        result.give_access    = false;
                        result.request_access = true;
                        pendingResults.put(childIdStr + '|request', result);
                    }
                    
                    
                    if (!wantsGive && !wantsRequest) {
                        
                        Account_Head_Relationship__c plainJunction = new Account_Head_Relationship__c(
                            Member_Account__c            = parentAccount.Id,
                            Authorized_Account_Access__c = childId,
                            Relationship__c              = String.isNotBlank(cr.relationship)  ? cr.relationship  : null,
                            Portal_Access_Status__c      = String.isNotBlank(cr.portal_status) ? cr.portal_status : null,
                            Give_Access__c               = false,
                            Request_Access__c            = false
                        );
                        toInsert.add(plainJunction);
                        
                        ChildResult result = new ChildResult();
                        result.firstName      = cr.firstName;
                        result.lastName       = cr.lastName;
                        result.childAccountId = childIdStr;
                        result.give_access    = false;
                        result.request_access = false;
                        pendingResults.put(childIdStr + '|plain', result);
                    }
                }
                
                
                if (!toInsert.isEmpty()) {
                    insert toInsert;
                    
                   
                    for (Account_Head_Relationship__c j : toInsert) {
                        
                        String  cId     = String.valueOf(j.Authorized_Account_Access__c);
                        String  slotKey = j.Give_Access__c    == true ? cId + '|give'
                            : j.Request_Access__c == true ? cId + '|request'
                                :                               cId + '|plain';
                        ChildResult r = pendingResults.get(slotKey);
                        if (r != null) {
                            r.success = true;
                            r.message = 'Account Head Relationship created successfully.';
                            if (j.Give_Access__c == true) {
                                r.give_access_rel_id = j.Id;
                            } else if (j.Request_Access__c == true) {
                                r.request_access_rel_id = j.Id;
                            } else {
                                r.relationshipId = j.Id;
                            }
                            linkResults.add(r);
                        }
                    }
                    
                }
            }
            
            
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
    
    
    private static String buildKey(String fn, String ln, String em, String mob) {
        return (em.trim().toLowerCase() + '|' + normalizePhone(mob)).toLowerCase();
    }
    
    private static String stripSpaces(String name) {
        if (String.isBlank(name)) return '';
        return name.replaceAll('\\s+', '');
    }
    
    private static String normalizePhone(String phone) {
        if (String.isBlank(phone)) return '';
        
        String digits = phone.replaceAll('[^0-9]', '');
        if (digits.length() > 10) {
            digits = digits.substring(digits.length() - 10);
        }
        
        return digits;
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
        global String  give_access_rel_id;    
        global String  request_access_rel_id; 
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