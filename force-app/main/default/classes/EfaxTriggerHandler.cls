public class EfaxTriggerHandler {
    
    
    public static void onBeforeInsert(List<smsefax_guru__eFAX__c> lstFax) {
        
        Map<Id, List<smsefax_guru__eFAX__c>> mapParentId = new Map<Id, List<smsefax_guru__eFAX__c>>();
        
        
        for (smsefax_guru__eFAX__c oFax : lstFax) {
            
            String recordTypeName = Schema.getGlobalDescribe().get('smsefax_guru__eFAX__c').getDescribe().getRecordTypeInfosById().get(oFax.RecordTypeId).getName();
            if (recordTypeName == 'OutBound eFAX' && String.isNotBlank(oFax.smsefax_guru__Parent_Record_Id__c) && ((Id) oFax.smsefax_guru__Parent_Record_Id__c).getSObjectType().getDescribe().getName().equalsIgnoreCase('Account') && oFax.smsefax_guru__Send_Cover_Letter__c) {
                if (!mapParentId.containsKey(oFax.smsefax_guru__Parent_Record_Id__c)) {
                    mapParentId.put(oFax.smsefax_guru__Parent_Record_Id__c, new List<smsefax_guru__eFAX__c>());
                }
                mapParentId.get(oFax.smsefax_guru__Parent_Record_Id__c).add(oFax);   
            }
        }
        
        if (!mapParentId.isEmpty()) {
            List<Account> lstAccount = [SELECT Id FROM Account WHERE Id IN :mapParentId.keySet()];
            
            if(lstAccount.size()>0){
                for (Account oAccount : lstAccount) {
                    if (mapParentId.get(oAccount.Id) != null){
                        sendReporteFax(mapParentId.get(oAccount.Id), oAccount);
                    }
                    
                }
            }
        }
    }
    
    
    private static void sendReporteFax(List<smsefax_guru__eFAX__c> lstFax, Account oAccount) {
        
        for (smsefax_guru__eFAX__c oFax : lstFax) {
            ContentVersion oCoverContent = getFaxCoverLetter(oFax,oAccount);
            oFax.smsefax_guru__Cover_Letter_Document_ID__c = oCoverContent.ContentDocumentId;
            oFax.smsefax_guru__Account__c = oAccount.Id;
            oFax.smsefax_guru__Send_Cover_Letter__c = true;
        }
    }
    
    private static ContentVersion getFaxCoverLetter(smsefax_guru__eFAX__c oFax,Account oAccount) {
        
        String sHTML = '';
        sHTML += '<!DOCTYPE html>';
        sHTML += '<html lang=\"en\">';
        sHTML += '<head>';
        sHTML += '<meta charset=\"UTF-8\">';
        sHTML += '<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">';
        sHTML += '<title>BatonCare Fax Cover Sheet</title>';
        sHTML += '<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;600&display=swap" rel="stylesheet">';
        sHTML += '<style>';
        sHTML += 'html, body { height: 100%; margin: 0; padding: 0; font-family: \'Poppins\', sans-serif; color: #222; }';
        sHTML += 'body { display: flex; flex-direction: column; min-height: 100vh; }';
        
        sHTML += '.header { text-align: center; margin: 0; }';
        sHTML += '.header h1 { font-size: 70px; margin: 0; font-weight: bold; }';
        sHTML += '.header span { font-weight: 300; }';
        sHTML += '.header p { font-size: 25px; margin: 4px 0 0 0; }';
        
        // Middle section styling (larger space without box)
        sHTML += '.middle { flex: 1; display: flex; justify-content: center; align-items: center;flex-direction: column; min-height: 500px; }';
        sHTML += '.disclaimer { margin-top: 120px; max-width: 80%; font-size: 16px; text-align: justify; text-justify: inter-word; line-height: 1.4;}';
        sHTML += '.form-section { text-align: left; }'; // removed box styling
        sHTML += '.form-section div { margin-bottom: 12px; font-size: 23px; }';
        sHTML += '.label { font-weight: bold; display: inline-block; width: 250px; vertical-align: middle; }';
        sHTML += '.value { font-size: 18px; vertical-align: middle; }';
        
        // Footer styling
        sHTML += '.footer { text-align: center; font-size: 24px; padding: 20px 0; }';
        sHTML += '.footer h1 { font-size: 30px; margin: 0; }';
        sHTML += '.footer span { font-weight: 100; }';
        sHTML += '.footer p { font-size: 17px; margin: 4px 0; }';
        sHTML += '</style>';
        
        sHTML += '</head>';
        sHTML += '<body>';
        
        // Header at top
        sHTML += '<div class=\"header\">';
        sHTML += '<h1><strong>Baton</strong><span>Care</span></h1>';
        sHTML += '<p><i>Your Health, Our Priority</i></p>';
        sHTML += '</div>';
        
        // Middle section (vertically centered)
        sHTML += '<div class=\"middle\">';
        sHTML += '<div class=\"form-section\">';
        sHTML += '<div><span class=\"label\">To:</span> <span class=\"value\">' + (oFax.Recipient_Name__c != null ? oFax.Recipient_Name__c : '') + '</span></div>';
        sHTML += '<div><span class=\"label\">Fax:</span> <span class=\"value\">' + (oFax.smsefax_guru__Customer_s_eFAX_Number__c != null ? oFax.smsefax_guru__Customer_s_eFAX_Number__c : '') + '</span></div>';
        sHTML += '<div><span class=\"label\">From:</span> <span class=\"value\">' + (oFax.Organization__c != null ? oFax.Organization__c : '') + '</span></div>';
        if(oFax.Fax_Date__c != null){
            String monthStr = (oFax.Fax_Date__c.month() < 10) ? '0' + String.valueOf(oFax.Fax_Date__c.month()) : String.valueOf(oFax.Fax_Date__c.month());
            String dayStr   = (oFax.Fax_Date__c.day() < 10) ? '0' + String.valueOf(oFax.Fax_Date__c.day())     : String.valueOf(oFax.Fax_Date__c.day());
            String yearStr  = String.valueOf(oFax.Fax_Date__c.year());
            String formattedDate = monthStr + '/' + dayStr + '/' + yearStr;
            sHTML += '<div><span class=\"label\">Date:</span> <span class=\"value\">' + formattedDate + '</span></div>';
        }
        sHTML += '<div><span class=\"label\">Pages (including cover):</span> <span class=\"value\">' + (oFax.smsefax_guru__Pages_Submitted__c != null ? String.valueOf(oFax.smsefax_guru__Pages_Submitted__c) : '') + '</span></div>';
        sHTML += '<div><span class=\"label\">Subject:</span> <span class=\"value\">' + (oFax.smsefax_guru__Account__c != null ? oFax.Account_Name__c : '') + '</span></div>';
        sHTML += '<div><span class=\"label\">Notes:</span> <span class=\"value\">' + (oFax.Notes__c != null ? oFax.Notes__c : '') + '</span></div>';
        sHTML += '</div>'; // form-section
        sHTML += '<div class="disclaimer">';
        sHTML += 'This fax may contain privileged or confidential information and is intended ';
        sHTML += 'for the exclusive use of the addressee(s). If you are not an intended recipient, ';
        sHTML += 'please notify sender and destroy all copies. Any unauthorized review, use, ';
        sHTML += 'disclosure, or distribution is prohibited and may result in legal sanction.';
        sHTML += '</div>';
        sHTML += '</div>'; // middle
        
        // Footer at bottom
        sHTML += '<div class=\"footer\">';
        sHTML += '<h1><strong>Baton</strong><span>Care</span></h1>';
        sHTML += '<p>980 North Federal Highway, Suite 110 #1068, Boca Raton, FL 33432</p>';
        sHTML += '<p>Main (561)303-0007 &middot; Fax (561)285-1983 &middot; support@batoncare.com</p>';
        sHTML += '</div>';
        
        sHTML += '</body>';
        sHTML += '</html>';
        
        
        return createCoverLetterFile(sHTML, oAccount.Id,'.html');
    }
    
    private static ContentVersion createCoverLetterFile(String sHTML, Id sParentId, String sExtension) {
        Blob blobHTML = Blob.valueOf(sHTML);
        
        ContentVersion objCV = new ContentVersion(
            Title = 'Cover_Letter_' + sParentId,
            PathOnClient = 'Cover_Letter_' + sParentId + sExtension,
            VersionData = blobHTML
        );
        
        insert objCV;
        
        objCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :objCV.Id LIMIT 1];
        
        return objCV;
    }
}