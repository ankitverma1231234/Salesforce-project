/**
 * @description Handler for CoverageBenefitItemTrigger.
 *
 *  Responsibilities
 *  ─────────────────
 *  • Filter records where CoverageBenefitId is not null.
 *  • On update, skip records whose CoverageBenefitId has not changed.
 *  • Collect valid CoverageBenefitItem Ids and hand off to
 *    MemberPlanSyncService.
 */
public without sharing class CoverageBenefitItemTriggerHandler {

    /**
     * @param newRecords  Trigger.new list
     * @param oldMap      Trigger.oldMap (null on insert)
     */
    public static void handle(
        List<CoverageBenefitItem> newRecords,
        Map<Id, CoverageBenefitItem> oldMap
    ) {
        Set<Id> coverageBenefitItemIds = new Set<Id>();

        for (CoverageBenefitItem cbi : newRecords) {
            // Guard: parent lookup must be populated
            if (cbi.CoverageBenefitId == null) {
                continue;
            }

            // On update: only process if a relevant field has changed
            if (oldMap != null) {
                CoverageBenefitItem oldCbi = oldMap.get(cbi.Id);
                if (!hasRelevantChange(cbi, oldCbi)) {
                    continue;
                }
            }

            coverageBenefitItemIds.add(cbi.Id);
        }

        if (!coverageBenefitItemIds.isEmpty()) {
            MemberPlanSyncService.syncFromCoverageBenefitItems(coverageBenefitItemIds);
        }
    }

    // ─── Private helpers ────────────────────────────────────────────────────

    /**
     * Returns true when any field that is sent to the third party has changed.
     * Extend this list if more fields are added to the payload.
     */
    private static Boolean hasRelevantChange(
        CoverageBenefitItem newCbi,
        CoverageBenefitItem oldCbi
    ) {
        return newCbi.CoverageBenefitId != oldCbi.CoverageBenefitId
            || newCbi.MemberId          != oldCbi.MemberId
            || newCbi.Name              != oldCbi.Name;
    }
}