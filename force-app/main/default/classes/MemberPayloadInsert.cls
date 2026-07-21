public with sharing class MemberPayloadInsert {
    public static void handle(List<Member_Payload__c> newRecords) {

        List<Member_Payload__c> validRecords = new List<Member_Payload__c>();
        for (Member_Payload__c rec : newRecords) {
            if (String.isNotBlank(rec.Payload_JSON__c)) {
                validRecords.add(rec);
            }
        }

        if (validRecords.isEmpty()) return;

        Set<Id> primaryAccountIds = new Set<Id>();
        for (Member_Payload__c rec : validRecords) {
            if (rec.Primary_Account__c != null) {
                primaryAccountIds.add(rec.Primary_Account__c);
            }
        }

        Map<Id, Account> primaryAccountMap = new Map<Id, Account>(
            [SELECT Id, Name FROM Account WHERE Id IN :primaryAccountIds]
        );

        Id personAccountRTId = getPersonAccountRecordTypeId();

        List<Account>                      accountsToInsert    = new List<Account>();
        List<Account>                      guestsToInsert      = new List<Account>();
        List<Member_Payload__c>            stagingToUpdate     = new List<Member_Payload__c>();

        Map<Id, List<Map<String, Object>>> stagingToMembersMap = new Map<Id, List<Map<String, Object>>>();
        Map<Id, List<Map<String, Object>>> stagingToGuestsMap  = new Map<Id, List<Map<String, Object>>>();
        Map<Id, Id>                        stagingToPrimaryMap = new Map<Id, Id>();
        Map<Id, Account>                   primaryAccountUpdateMap = new Map<Id, Account>();
        Map<Id, Map<String, Id>> stagingToIdResolutionMap = new Map<Id, Map<String, Id>>();

        List<Id>     memberInsertStagingIds = new List<Id>();
        List<String> memberInsertTempIds    = new List<String>();

        for (Member_Payload__c rec : validRecords) {
            try {
                Map<String, Object> payload =
                    (Map<String, Object>) JSON.deserializeUntyped(rec.Payload_JSON__c);

                if (rec.Primary_Account__c == null ||
                    !primaryAccountMap.containsKey(rec.Primary_Account__c)) continue;

                stagingToPrimaryMap.put(rec.Id, rec.Primary_Account__c);

                Map<String, Object> localIdMap = stagingToIdResolutionMap.containsKey(rec.Id)
                    ? stagingToIdResolutionMap.get(rec.Id)
                    : null;

                if (!stagingToIdResolutionMap.containsKey(rec.Id)) {
                    stagingToIdResolutionMap.put(rec.Id, new Map<String, Id>());
                }

                Map<String, Object> primaryMember = payload.get('primaryMember') != null
                    ? (Map<String, Object>) payload.get('primaryMember')
                    : null;

                if (primaryMember != null) {
                    Date primaryDob = parseDob((String) primaryMember.get('dob'));
                    if (primaryDob != null) {
                        primaryAccountUpdateMap.put(rec.Primary_Account__c, new Account(
                            Id                = rec.Primary_Account__c,
                            Date_of_Birth__pc = primaryDob
                        ));
                    }
                    
                    String primaryLocalId = (String) primaryMember.get('id');
                    if (String.isNotBlank(primaryLocalId)) {
                        stagingToIdResolutionMap.get(rec.Id).put(primaryLocalId, rec.Primary_Account__c);
                    }
                }

                List<Object> membersArray = (List<Object>) payload.get('members');
                if (membersArray != null && !membersArray.isEmpty()) {

                    List<Map<String, Object>> memberDataList = new List<Map<String, Object>>();

                    for (Object memberObj : membersArray) {
                        Map<String, Object> member = (Map<String, Object>) memberObj;
                        if (member == null) continue;

                        Map<String, Object> address = member.get('address') != null
                            ? (Map<String, Object>) member.get('address')
                            : new Map<String, Object>();

                        Account acc = new Account(
                            FirstName                  = (String) member.get('firstName'),
                            LastName                   = String.isNotBlank((String) member.get('lastName'))
                                                         ? (String) member.get('lastName')
                                                         : '',
                            PersonEmail                = (String) member.get('email'),
                            PersonMobilePhone          = (String) member.get('phone'),
                            Biological_Sex_at_Birth__c = (String) member.get('gender'),
                            Date_of_Birth__pc          = parseDob((String) member.get('dob')),
                            PersonMailingStreet        = (String) address.get('fullAddress'),
                            PersonMailingCity          = (String) address.get('city'),
                            PersonMailingState         = (String) address.get('state'),
                            PersonMailingPostalCode    = (String) address.get('zipCode'),
                            PersonMailingCountry       = (String) address.get('country'),
                            RecordTypeId               = personAccountRTId
                        );

                        accountsToInsert.add(acc);
                        memberDataList.add(member);

                        memberInsertStagingIds.add(rec.Id);
                        memberInsertTempIds.add((String) member.get('id'));
                    }

                    stagingToMembersMap.put(rec.Id, memberDataList);
                }

                List<Object> guestsArray = (List<Object>) payload.get('guests');
                if (guestsArray != null && !guestsArray.isEmpty()) {

                    List<Map<String, Object>> guestDataList = new List<Map<String, Object>>();

                    for (Object guestObj : guestsArray) {
                        Map<String, Object> guest = (Map<String, Object>) guestObj;
                        if (guest == null) continue;

                        Boolean isGuest = String.valueOf(guest.get('is_guest')) == 'true';

                        Account guestAcc = new Account(
                            FirstName         = (String) guest.get('firstName'),
                            LastName          = String.isNotBlank((String) guest.get('lastName'))
                                                ? (String) guest.get('lastName')
                                                : '',
                            PersonEmail       = (String) guest.get('email'),
                            PersonMobilePhone = (String) guest.get('phone'),
                            Is_Guest__c       = isGuest,
                            RecordTypeId      = personAccountRTId
                        );

                        guestsToInsert.add(guestAcc);
                        guestDataList.add(guest);
                    }

                    stagingToGuestsMap.put(rec.Id, guestDataList);
                }

            } catch (Exception e) {
                System.debug('Parse error for rec ' + rec.Id + ': '
                    + e.getMessage() + ' Line: ' + e.getLineNumber());
                stagingToUpdate.add(new Member_Payload__c(
                    Id               = rec.Id,
                    Status__c        = 'Failed',
                    Error_Message__c = 'Parse error: ' + e.getMessage()
                ));
            }
        }

        if (!accountsToInsert.isEmpty()) {
            Database.SaveResult[] memberResults = Database.insert(accountsToInsert, false);
            for (Integer i = 0; i < memberResults.size(); i++) {
                if (!memberResults[i].isSuccess()) {
                    System.debug('Member Account insert failed [' + i + ']: '
                        + memberResults[i].getErrors()[0].getMessage());
                    continue;
                }

                Id stagingId    = memberInsertStagingIds[i];
                String tempId   = memberInsertTempIds[i];
                if (String.isNotBlank(tempId)) {
                    if (!stagingToIdResolutionMap.containsKey(stagingId)) {
                        stagingToIdResolutionMap.put(stagingId, new Map<String, Id>());
                    }
                    stagingToIdResolutionMap.get(stagingId).put(tempId, memberResults[i].getId());
                }
            }
        }

        if (!primaryAccountUpdateMap.isEmpty()) {
            Database.SaveResult[] primaryUpdateResults =
                Database.update(primaryAccountUpdateMap.values(), false);
            for (Integer i = 0; i < primaryUpdateResults.size(); i++) {
                if (!primaryUpdateResults[i].isSuccess()) {
                    System.debug('Primary Account DOB update failed [' + i + ']: '
                        + primaryUpdateResults[i].getErrors()[0].getMessage());
                }
            }
        }

        // ── Insert Guest Accounts then create AHR records ────────────────────
        if (!guestsToInsert.isEmpty()) {
            Database.SaveResult[] guestResults = Database.insert(guestsToInsert, false);

            List<GuestAccountRelationshipHandler.GuestAHRRequest> ahrRequests =
                new List<GuestAccountRelationshipHandler.GuestAHRRequest>();

            Integer guestIndex = 0;
            for (Member_Payload__c rec : validRecords) {
                if (!stagingToGuestsMap.containsKey(rec.Id)) continue;

                List<Map<String, Object>> guestDataList = stagingToGuestsMap.get(rec.Id);
                Map<String, Id> localIdMap = stagingToIdResolutionMap.get(rec.Id);

                for (Map<String, Object> guestData : guestDataList) {
                    if (guestIndex >= guestResults.size()) break;

                    Database.SaveResult gr = guestResults[guestIndex];
                    guestIndex++;

                    if (!gr.isSuccess()) {
                        System.debug('Guest Account insert failed: '
                            + gr.getErrors()[0].getMessage());
                        continue;
                    }

                    Id guestAccountId = gr.getId();

                    List<Object> memberAccessIds =
                        (List<Object>) guestData.get('memberAccessIds');

                    if (memberAccessIds == null || memberAccessIds.isEmpty()) continue;

                    List<Id> resolvedMemberIds = new List<Id>();
                    for (Object idObj : memberAccessIds) {
                        String idStr = (String) idObj;
                        if (String.isBlank(idStr)) continue;

                        Id resolvedId = (localIdMap != null) ? localIdMap.get(idStr) : null;

                        if (resolvedId == null) {
                            try {
                                resolvedId = (Id) idStr;
                            } catch (Exception ex) {
                                System.debug('Could not resolve member access id: ' + idStr);
                                continue;
                            }
                        }

                        resolvedMemberIds.add(resolvedId);
                    }

                    if (!resolvedMemberIds.isEmpty()) {
                        ahrRequests.add(new GuestAccountRelationshipHandler.GuestAHRRequest(
                            guestAccountId,
                            resolvedMemberIds
                        ));
                    }
                }
            }

            if (!ahrRequests.isEmpty()) {
                GuestAccountRelationshipHandler.createAHRRecords(ahrRequests);
            }
        }

        List<Contact> contactsToInsert = new List<Contact>();

        for (Member_Payload__c rec : validRecords) {
            if (!stagingToMembersMap.containsKey(rec.Id)) continue;

            Id primaryAccId = stagingToPrimaryMap.get(rec.Id);
            List<Map<String, Object>> memberDataList = stagingToMembersMap.get(rec.Id);

            for (Map<String, Object> member : memberDataList) {
                if (member == null) continue;

                Map<String, Object> address = member.get('address') != null
                    ? (Map<String, Object>) member.get('address')
                    : new Map<String, Object>();

                contactsToInsert.add(new Contact(
                    FirstName         = (String) member.get('firstName'),
                    LastName          = String.isNotBlank((String) member.get('lastName'))
                                        ? (String) member.get('lastName')
                                        : '',
                    Maiden_Name__c    = (String) member.get('maidenName'),
                    Gender            = (String) member.get('gender'),
                    Emergency_Contact_Relationship__c = (String) member.get('relationship'),
                    Email             = (String) member.get('email'),
                    MobilePhone       = (String) member.get('phone'),
                    Account__c        = primaryAccId,
                    MailingStreet     = (String) address.get('fullAddress'),
                    MailingCity       = (String) address.get('city'),
                    MailingState      = (String) address.get('state'),
                    MailingPostalCode = (String) address.get('zipCode'),
                    MailingCountry    = (String) address.get('country')
                ));
            }
        }

        if (!contactsToInsert.isEmpty()) {
            Database.SaveResult[] contactResults = Database.insert(contactsToInsert, false);
            for (Integer i = 0; i < contactResults.size(); i++) {
                if (!contactResults[i].isSuccess()) {
                    System.debug('Contact insert failed [' + i + ']: '
                        + contactResults[i].getErrors()[0].getMessage());
                }
            }
        }

        // ── Update staging records ────────────────────────────────────────────
        if (!stagingToUpdate.isEmpty()) {
            update stagingToUpdate;
        }
    }

    // ── DOB parser ───────────────────────────────────────────────────────────
    private static Date parseDob(String dobStr) {
        if (String.isBlank(dobStr)) return null;
        try {
            List<String> parts = dobStr.split('-');
            if (parts.size() == 3) {
                return Date.newInstance(
                    Integer.valueOf(parts[2]),
                    Integer.valueOf(parts[0]),
                    Integer.valueOf(parts[1])
                );
            }
        } catch (Exception e) {
            System.debug('DOB parse error: ' + e.getMessage());
        }
        return null;
    }

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rtList = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType  = true
            LIMIT 1
        ];
        return rtList.isEmpty() ? null : rtList[0].Id;
    }
}