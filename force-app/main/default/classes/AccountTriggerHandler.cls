public without sharing class AccountTriggerHandler {
    public static void postChatterOnOwnerChange(Map<Id,Account> oldAccounts, List<Account> accList){
        // Constant for Unassigned user ID and name
        //final Id UNASSIGNED_USER_ID = System.Label.Unassigned;
        User u = [Select ID FROM User WHERE LastName = 'Unassigned' LIMIT 1];
        List<ConnectApi.MentionSegmentInput> mentions = new List<ConnectApi.MentionSegmentInput>();
        List<FeedItem> feedItems = new List<FeedItem>();
        
        for (Account acc: accList) { 
            // Only act if owner changed and new owner is the Unassigned user
            if (acc.OwnerId != oldAccounts.get(acc.Id).OwnerId && acc.OwnerId == u.Id) {
                ConnectApi.FeedItemInput input = new ConnectApi.FeedItemInput();
                input.feedElementType = ConnectApi.FeedElementType.FeedItem;
                input.subjectId = acc.Id;
                
                // Build rich text body with @mention
                ConnectApi.MessageBodyInput body = new ConnectApi.MessageBodyInput();
                body.messageSegments = new List<ConnectApi.MessageSegmentInput>();
                
                
                ConnectApi.TextSegmentInput text = new ConnectApi.TextSegmentInput();
                text.text = System.Label.Unassigned_Chatter;
                body.messageSegments.add(text);
                
                ConnectApi.MentionSegmentInput mention = new ConnectApi.MentionSegmentInput();
                mention.id = System.Label.MelaUserId;
                
                body.messageSegments.add(mention);
                ConnectApi.MentionSegmentInput mention1 = new ConnectApi.MentionSegmentInput();
                mention1.id = System.Label.DanielUserId;
                
                body.messageSegments.add(mention1);
                ConnectApi.MentionSegmentInput mention2 = new ConnectApi.MentionSegmentInput();
                mention2.id = System.Label.BrianUserId;
                
                body.messageSegments.add(mention2);
                
                input.body = body;
                
                // Post to record feed as current user
                if(!Test.isRunningTest()){
                	ConnectApi.ChatterFeeds.postFeedElement(null, input);
                }
            }
        }
    }
}