public class ContentDocumentLinkHandler {
    public static void updateVisibility(List<ContentDocumentLink> newRecords) {
        for (ContentDocumentLink cdl : newRecords) {
            if (cdl.LinkedEntityId.getSObjectType().getDescribe().getName() == 'Account') {
                cdl.Visibility = 'AllUsers';
                cdl.ShareType = 'V';
            }
        }
    }
}