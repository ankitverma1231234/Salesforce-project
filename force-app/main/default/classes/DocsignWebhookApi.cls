@RestResource(urlMapping='/docsignwebhook/*')
global without sharing class DocsignWebhookApi {

    private static final Set<String> SUPPORTED_EVENT_TYPES = new Set<String>{
        'document_sent',
        'document_opened',
        'document_viewed',
        'recipient_signed',
        'recipient_declined',
        'document_expired',
        'signed_copy_generated'
    };

    private static final Set<String> ACTOR_REQUIRED_EVENTS = new Set<String>{
        'document_opened',
        'document_viewed',
        'recipient_signed',
        'recipient_declined'
    };

    @HttpPost
    global static void receiveWebhook() {
        RestResponse res = RestContext.response;
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }
        res.addHeader('Content-Type', 'application/json');

        try {
            String requestBody = null;
            if (RestContext.request != null && RestContext.request.requestBody != null) {
                requestBody = RestContext.request.requestBody.toString();
            }

            if (String.isBlank(requestBody)) {
                writeResponse(400, buildErrorResponse('Empty request body.'));
                return;
            }

            WebhookPayload payload =
                (WebhookPayload) JSON.deserialize(requestBody, WebhookPayload.class);

            normalizePayload(payload);

            List<String> validationErrors = validatePayload(payload);
            if (!validationErrors.isEmpty()) {
                ApiResponse errorResponse = buildErrorResponse('Payload validation failed.');
                errorResponse.errors = validationErrors;
                writeResponse(400, errorResponse);
                return;
            }

            Doc_Flow_Analytics__c analyticsRecord = mapToAnalyticsRecord(payload, requestBody);

            upsert analyticsRecord Event_Id__c;

            ApiResponse successResponse = new ApiResponse();
            successResponse.success = true;
            successResponse.message = 'Webhook received and analytics record saved successfully.';
            successResponse.event_id = payload.event_id;
            successResponse.event_type = payload.event_type;
            successResponse.document_id = payload.document != null ? payload.document.document_id : null;
            successResponse.analytics_record_id = analyticsRecord.Id;
            successResponse.linked_parent_type = getLinkedParentType(analyticsRecord);
            successResponse.linked_parent_id = getLinkedParentId(analyticsRecord);
            successResponse.download_url = payload.document != null ? payload.document.download_url : null;
            successResponse.requires_document_fetch = shouldFetchSignedCopy(payload);

            writeResponse(200, successResponse);

        } catch (System.JSONException je) {
            ApiResponse errorResponse = buildErrorResponse('Invalid JSON payload.');
            errorResponse.errors = new List<String>{ je.getMessage() };
            writeResponse(400, errorResponse);

        } catch (DmlException de) {
            ApiResponse errorResponse = buildErrorResponse('Record could not be saved.');
            errorResponse.errors = new List<String>{ de.getMessage() };
            writeResponse(500, errorResponse);

        } catch (Exception e) {
            ApiResponse errorResponse = buildErrorResponse('Unexpected server error.');
            errorResponse.errors = new List<String>{ e.getMessage() };
            writeResponse(500, errorResponse);
        }
    }

    private static Doc_Flow_Analytics__c mapToAnalyticsRecord(WebhookPayload payload, String rawJson) {
        Doc_Flow_Analytics__c rec = new Doc_Flow_Analytics__c();

        rec.Event_Id__c = trimTo(payload.event_id, 100);
        rec.Event_Type__c = trimTo(payload.event_type, 80);
        rec.Event_Time__c = parseIsoDateTime(payload.event_time);
        rec.Source_System__c = trimTo(payload.source_system, 80);
        rec.Environment__c = trimTo(payload.environment, 40);

        if (payload.document != null) {
            rec.Document_Id__c = trimTo(payload.document.document_id, 100);
            rec.Document_Name__c = trimTo(payload.document.document_name, 255);
            rec.Document_Status__c = trimTo(payload.document.document_status, 80);
            rec.Public_Link__c = trimTo(payload.document.public_link, 255);
            rec.Download_URL__c = trimTo(payload.document.download_url, 255);
            rec.Document_Created_Time__c = parseIsoDateTime(payload.document.created_time);
            rec.Document_Completed_Time__c = parseIsoDateTime(payload.document.completed_time);
        }

        if (payload.actor_recipient != null) {
            rec.Actor_Recipient_Id__c = trimTo(payload.actor_recipient.recipient_id, 100);
            rec.Actor_Name__c = trimTo(payload.actor_recipient.name, 255);
            rec.Actor_Email__c = trimTo(payload.actor_recipient.email, 80);
            rec.Actor_Role__c = trimTo(payload.actor_recipient.role, 100);
            rec.Routing_Order__c = payload.actor_recipient.routing_order;
            rec.Recipient_Status__c = trimTo(payload.actor_recipient.status, 80);
            rec.Document_Recipient_Key__c = trimTo(payload.actor_recipient.document_recipient_key, 255);
        }

        if (payload.analytics != null) {
            rec.IP_Address__c = trimTo(payload.analytics.ip_address, 100);
            rec.User_Agent__c = trimTo(payload.analytics.user_agent, 5000);
            rec.Device_Type__c = trimTo(payload.analytics.device_type, 40);
            rec.Browser__c = trimTo(payload.analytics.browser, 80);
            rec.OS__c = trimTo(payload.analytics.os, 80);
        }

        if (payload.salesforce_context != null) {
            rec.Source_Record_Id__c = trimTo(payload.salesforce_context.source_record_id, 18);
            rec.Source_Object__c = trimTo(payload.salesforce_context.source_object, 80);

            if (isValidIdWithPrefix(payload.salesforce_context.contact_id, '003')) {
                rec.Contact__c = payload.salesforce_context.contact_id;
            }


            if (isValidIdWithPrefix(payload.salesforce_context.account_id, '001')) {
                rec.Person_Account__c = payload.salesforce_context.account_id;
            } else if (equalsIgnoreCase(payload.salesforce_context.source_object, 'Account')
                && isValidIdWithPrefix(payload.salesforce_context.source_record_id, '001')) {
                rec.Person_Account__c = payload.salesforce_context.source_record_id;
            }

            if (equalsIgnoreCase(payload.salesforce_context.source_object, 'Opportunity')
                && isValidIdWithPrefix(payload.salesforce_context.source_record_id, '006')) {
                rec.Opportunity__c = payload.salesforce_context.source_record_id;
            }
        }

        rec.Recipients_Snapshot__c = truncateLongText(
            payload.recipients != null ? JSON.serialize(payload.recipients) : null,
            131072
        );

        rec.Raw_Payload__c = truncateLongText(rawJson, 131072);
        rec.Processing_Status__c = shouldFetchSignedCopy(payload) ? 'Pending File Fetch' : 'Processed';
        rec.Error_Message__c = null;

        return rec;
    }

    private static void normalizePayload(WebhookPayload payload) {
        if (payload == null) {
            return;
        }

        if (!String.isBlank(payload.event_type)) {
            payload.event_type = payload.event_type.trim().toLowerCase();
        }

        if (payload.document != null && payload.actor_recipient != null) {
            if (String.isBlank(payload.actor_recipient.document_recipient_key)
                && !String.isBlank(payload.document.document_id)
                && !String.isBlank(payload.actor_recipient.recipient_id)) {

                payload.actor_recipient.document_recipient_key =
                    payload.document.document_id + '_' + payload.actor_recipient.recipient_id;
            }
        }

        if (payload.document != null && payload.recipients != null) {
            for (RecipientInfo rec : payload.recipients) {
                if (rec == null) {
                    continue;
                }

                if (String.isBlank(rec.document_recipient_key)
                    && !String.isBlank(payload.document.document_id)
                    && !String.isBlank(rec.recipient_id)) {

                    rec.document_recipient_key =
                        payload.document.document_id + '_' + rec.recipient_id;
                }
            }
        }
    }

    private static List<String> validatePayload(WebhookPayload payload) {
        List<String> errors = new List<String>();

        if (payload == null) {
            errors.add('Payload could not be parsed.');
            return errors;
        }

        if (String.isBlank(payload.event_id)) {
            errors.add('event_id is required.');
        }

        if (String.isBlank(payload.event_type)) {
            errors.add('event_type is required.');
        } else if (!SUPPORTED_EVENT_TYPES.contains(payload.event_type)) {
            errors.add('Unsupported event_type: ' + payload.event_type);
        }

        if (String.isBlank(payload.event_time)) {
            errors.add('event_time is required.');
        } else if (parseIsoDateTime(payload.event_time) == null) {
            errors.add('event_time must be a valid ISO datetime like 2026-03-25T12:18:00Z.');
        }

        if (payload.document == null) {
            errors.add('document block is required.');
        } else {
            if (String.isBlank(payload.document.document_id)) {
                errors.add('document.document_id is required.');
            }

            if (String.isBlank(payload.document.document_status)) {
                errors.add('document.document_status is required.');
            }

            if (!String.isBlank(payload.document.created_time)
                && parseIsoDateTime(payload.document.created_time) == null) {
                errors.add('document.created_time is not a valid ISO datetime.');
            }

            if (!String.isBlank(payload.document.completed_time)
                && parseIsoDateTime(payload.document.completed_time) == null) {
                errors.add('document.completed_time is not a valid ISO datetime.');
            }

            if (!String.isBlank(payload.document.download_url)
                && !payload.document.download_url.startsWith('http')) {
                errors.add('document.download_url must be a valid URL.');
            }
        }

        if (payload.recipients == null || payload.recipients.isEmpty()) {
            errors.add('At least one recipient is required in recipients[].');
        } else {
            Set<String> recipientIds = new Set<String>();

            for (Integer i = 0; i < payload.recipients.size(); i++) {
                RecipientInfo rec = payload.recipients[i];

                if (rec == null) {
                    errors.add('recipients[' + i + '] is null.');
                    continue;
                }

                if (String.isBlank(rec.recipient_id)) {
                    errors.add('recipients[' + i + '].recipient_id is required.');
                } else {
                    if (recipientIds.contains(rec.recipient_id)) {
                        errors.add('Duplicate recipient_id found: ' + rec.recipient_id);
                    }
                    recipientIds.add(rec.recipient_id);
                }

                if (String.isBlank(rec.status)) {
                    errors.add('recipients[' + i + '].status is required.');
                }

                if (!String.isBlank(rec.signed_time)
                    && parseIsoDateTime(rec.signed_time) == null) {
                    errors.add('recipients[' + i + '].signed_time is not a valid ISO datetime.');
                }

                if (!String.isBlank(rec.declined_time)
                    && parseIsoDateTime(rec.declined_time) == null) {
                    errors.add('recipients[' + i + '].declined_time is not a valid ISO datetime.');
                }
            }

            if (payload.actor_recipient != null && !String.isBlank(payload.actor_recipient.recipient_id)) {
                if (!recipientIds.contains(payload.actor_recipient.recipient_id)) {
                    errors.add('actor_recipient.recipient_id must exist in recipients[].');
                }
            }
        }

        if (!String.isBlank(payload.event_type) && ACTOR_REQUIRED_EVENTS.contains(payload.event_type)) {
            if (payload.actor_recipient == null) {
                errors.add('actor_recipient is required for event_type = ' + payload.event_type);
            } else {
                if (String.isBlank(payload.actor_recipient.recipient_id)) {
                    errors.add('actor_recipient.recipient_id is required.');
                }

                if (String.isBlank(payload.actor_recipient.status)) {
                    errors.add('actor_recipient.status is required.');
                }
            }
        }

        if (payload.event_type == 'signed_copy_generated'
            && (payload.document == null || String.isBlank(payload.document.download_url))) {
            errors.add('document.download_url is required for signed_copy_generated.');
        }

        if (payload.salesforce_context != null
            && !String.isBlank(payload.salesforce_context.source_record_id)
            && String.isBlank(payload.salesforce_context.source_object)) {
            errors.add('salesforce_context.source_object is required when source_record_id is passed.');
        }

        if (payload.salesforce_context != null
            && !String.isBlank(payload.salesforce_context.source_record_id)
            && !String.isBlank(payload.salesforce_context.source_object)) {

            if (equalsIgnoreCase(payload.salesforce_context.source_object, 'Opportunity')
                && !isValidIdWithPrefix(payload.salesforce_context.source_record_id, '006')) {
                errors.add('Opportunity source_record_id must be a valid Opportunity Id.');
            }

            if (equalsIgnoreCase(payload.salesforce_context.source_object, 'Account')
                && !isValidIdWithPrefix(payload.salesforce_context.source_record_id, '001')) {
                errors.add('Account source_record_id must be a valid Account Id.');
            }
        }

        return errors;
    }

    private static Boolean shouldFetchSignedCopy(WebhookPayload payload) {
        return payload != null
            && payload.document != null
            && payload.event_type == 'signed_copy_generated'
            && !String.isBlank(payload.document.download_url);
    }

    private static Datetime parseIsoDateTime(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            String normalized = value.trim();

            if (normalized.contains('.')) {
                normalized = normalized.substring(0, normalized.indexOf('.'));
            }

            if (normalized.endsWith('Z')) {
                normalized = normalized.substring(0, normalized.length() - 1);
            }

            normalized = normalized.replace('T', ' ');
            return Datetime.valueOfGmt(normalized);
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean isValidIdWithPrefix(String value, String prefix) {
        if (String.isBlank(value)) {
            return false;
        }

        String v = value.trim();
        return (v.length() == 15 || v.length() == 18) && v.startsWith(prefix);
    }

    private static Boolean equalsIgnoreCase(String a, String b) {
        if (a == null || b == null) {
            return false;
        }
        return a.trim().toLowerCase() == b.trim().toLowerCase();
    }

    private static String trimTo(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        String v = value.trim();
        return v.length() > maxLength ? v.substring(0, maxLength) : v;
    }

    private static String truncateLongText(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }

    private static String getLinkedParentType(Doc_Flow_Analytics__c rec) {
        if (rec.Opportunity__c != null) {
            return 'Opportunity';
        }
        if (rec.Person_Account__c != null) {
            return 'Account';
        }
       
        return null;
    }

    private static String getLinkedParentId(Doc_Flow_Analytics__c rec) {
        if (rec.Opportunity__c != null) {
            return String.valueOf(rec.Opportunity__c);
        }
        if (rec.Person_Account__c != null) {
            return String.valueOf(rec.Person_Account__c);
        }
       
        return null;
    }

    private static void writeResponse(Integer statusCode, ApiResponse responseBody) {
        RestResponse res = RestContext.response;
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        res.addHeader('Content-Type', 'application/json');
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serializePretty(responseBody));
    }

    private static ApiResponse buildErrorResponse(String message) {
        ApiResponse response = new ApiResponse();
        response.success = false;
        response.message = message;
        return response;
    }

    global class ApiResponse {
        global Boolean success;
        global String message;
        global List<String> errors;

        global String event_id;
        global String event_type;
        global String document_id;
        global Id analytics_record_id;
        global String linked_parent_type;
        global String linked_parent_id;
        global String download_url;
        global Boolean requires_document_fetch;
    }

    global class WebhookPayload {
        global String event_id;
        global String event_type;
        global String event_time;
        global String source_system;
        global String environment;

        global DocumentInfo document;
        global ActorRecipientInfo actor_recipient;
        global List<RecipientInfo> recipients;
        global AnalyticsInfo analytics;
        global SalesforceContextInfo salesforce_context;
    }

    global class DocumentInfo {
        global String document_id;
        global String document_name;
        global String document_status;
        global String public_link;
        global String download_url;
        global String created_time;
        global String completed_time;
    }

    global class ActorRecipientInfo {
        global String recipient_id;
        global String name;
        global String email;
        global String role;
        global Integer routing_order;
        global String status;
        global String document_recipient_key;
    }

    global class RecipientInfo {
        global String recipient_id;
        global String name;
        global String email;
        global String role;
        global Integer routing_order;
        global String status;
        global String signed_time;
        global String declined_time;
        global String document_recipient_key;
    }

    global class AnalyticsInfo {
        global String ip_address;
        global String user_agent;
        global String device_type;
        global String browser;
        global String os;
    }

    global class SalesforceContextInfo {
        global String source_record_id;
        global String source_object;
        global String contact_id;
        global String lead_id;
        global String account_id;
    }
}