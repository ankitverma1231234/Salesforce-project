public class StripeSubscriptionHandler {
    
    public class Result {
        public Boolean success;
        public String message;

        public Result(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
    }

    public static Result handleSubscriptionCreated(Map<String, Object> subscription) {
        try {
            Integer maxAttempts = 5;
            Integer waitTimeMs = 2000;

            if (subscription == null) {
                return new Result(false, 'Subscription payload is null.');
            }

            // Extract subscription ID
            String subscriptionId = (String) subscription.get('id');
            if (String.isBlank(subscriptionId)) {
                return new Result(false, 'Subscription ID missing in payload.');
            }

            // Extract items
            Map<String, Object> items = (Map<String, Object>) subscription.get('items');
            if (items == null || !items.containsKey('data')) {
                return new Result(false, 'Subscription items missing or malformed.');
            }

            List<Object> dataList = (List<Object>) items.get('data');
            if (dataList == null || dataList.isEmpty()) {
                return new Result(false, 'Subscription items data is empty.');
            }

            Map<String, Object> firstItem = (Map<String, Object>) dataList[0];
            if (firstItem == null) {
                return new Result(false, 'First subscription item is null.');
            }

            // Extract current_period_start
            Object currentPeriodStartObj = firstItem.get('current_period_start');
            if (currentPeriodStartObj == null) {
                return new Result(false, 'current_period_start missing.');
            }

            Long currentPeriodStartEpoch;
            if (currentPeriodStartObj instanceof Integer) {
                currentPeriodStartEpoch = (Long) ((Integer) currentPeriodStartObj);
            } else {
                currentPeriodStartEpoch = (Long) currentPeriodStartObj;
            }

            // Convert epoch to DateTime
            DateTime currentPeriodStartDateTime = DateTime.newInstance(currentPeriodStartEpoch * 1000);
            Date currentPeriodStartDate = currentPeriodStartDateTime.date();

            // Extract recurring interval
            Map<String, Object> price = (Map<String, Object>) firstItem.get('price');
            if (price == null || !price.containsKey('recurring')) {
                return new Result(false, 'Price or recurring info missing.');
            }

            Map<String, Object> recurring = (Map<String, Object>) price.get('recurring');
            if (recurring == null) {
                return new Result(false, 'Recurring info missing.');
            }

            String interval = (String) recurring.get('interval');
            Object intervalCountObj = recurring.get('interval_count');
            if (interval == null || intervalCountObj == null) {
                return new Result(false, 'Interval or interval_count missing.');
            }

            // Safely cast interval_count to Integer
            Integer intervalCount;
            if (intervalCountObj instanceof Integer) {
                intervalCount = (Integer) intervalCountObj;
            } else if (intervalCountObj instanceof Long) {
                intervalCount = ((Long) intervalCountObj).intValue();
            } else {
                intervalCount = Integer.valueOf(String.valueOf(intervalCountObj));
            }

            // Calculate renewal date
            Date renewalDate;
            if (interval == 'year') {
                renewalDate = currentPeriodStartDate.addYears(intervalCount);
            } else if (interval == 'month') {
                renewalDate = currentPeriodStartDate.addMonths(intervalCount);
            } else if (interval == 'day') {
                renewalDate = currentPeriodStartDate.addDays(intervalCount);
            } else {
                return new Result(false, 'Unsupported interval: ' + interval);
            }

            // Try to find and update the related Opportunity
            List<Opportunity> opps = new List<Opportunity>();
            Opportunity opp = null;
            for (Integer attempt = 1; attempt <= maxAttempts; attempt++) {
                opps = [
                    SELECT Id, Renewal_Date__c
                    FROM Opportunity
                    WHERE Subscription_Id__c!= null AND Subscription_Id__c = :subscriptionId
                    LIMIT 1
                ];

                if (!opps.isEmpty()) {
                    opp = opps[0];
                    System.debug('Opportunity found on attempt ' + attempt);
                    break;
                }

                // Wait before retrying (busy-wait, since Apex doesn't allow Thread.sleep)
                if (!Test.isRunningTest()) {
                    Long startTime = System.now().getTime();
                    while (System.now().getTime() - startTime < waitTimeMs) {
                        
                   }
                }
            }
            

            if (opps.isEmpty()) {
                return new Result(false, 'No Opportunity found for Subscription ID: ' + subscriptionId);
            }
            opp.Renewal_Date__c = renewalDate;
            update opp;
            return new Result(true, 'Opportunity updated with renewal date: ' + renewalDate.format());

        } catch (Exception ex) {
            System.debug('Exception in handleSubscriptionCreated: ' + ex.getMessage());
            return new Result(false, 'Error: ' + ex.getMessage() + ' at line ' + ex.getLineNumber());
        }
    }
}