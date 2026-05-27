public class StateNormalizer {

    private static final Map<String, String> NAME_TO_CODE =
        new Map<String, String>{
            'ALABAMA'              => 'AL', 'ALASKA'               => 'AK',
            'ARIZONA'             => 'AZ', 'ARKANSAS'             => 'AR',
            'CALIFORNIA'          => 'CA', 'COLORADO'             => 'CO',
            'CONNECTICUT'         => 'CT', 'DELAWARE'             => 'DE',
            'FLORIDA'             => 'FL', 'GEORGIA'              => 'GA',
            'HAWAII'              => 'HI', 'IDAHO'                => 'ID',
            'ILLINOIS'            => 'IL', 'INDIANA'              => 'IN',
            'IOWA'                => 'IA', 'KANSAS'               => 'KS',
            'KENTUCKY'            => 'KY', 'LOUISIANA'            => 'LA',
            'MAINE'               => 'ME', 'MARYLAND'             => 'MD',
            'MASSACHUSETTS'       => 'MA', 'MICHIGAN'             => 'MI',
            'MINNESOTA'           => 'MN', 'MISSISSIPPI'          => 'MS',
            'MISSOURI'            => 'MO', 'MONTANA'              => 'MT',
            'NEBRASKA'            => 'NE', 'NEVADA'               => 'NV',
            'NEW HAMPSHIRE'       => 'NH', 'NEW JERSEY'           => 'NJ',
            'NEW MEXICO'          => 'NM', 'NEW YORK'             => 'NY',
            'NORTH CAROLINA'      => 'NC', 'NORTH DAKOTA'         => 'ND',
            'OHIO'                => 'OH', 'OKLAHOMA'             => 'OK',
            'OREGON'              => 'OR', 'PENNSYLVANIA'         => 'PA',
            'RHODE ISLAND'        => 'RI', 'SOUTH CAROLINA'       => 'SC',
            'SOUTH DAKOTA'        => 'SD', 'TENNESSEE'            => 'TN',
            'TEXAS'               => 'TX', 'UTAH'                 => 'UT',
            'VERMONT'             => 'VT', 'VIRGINIA'             => 'VA',
            'WASHINGTON'          => 'WA', 'WEST VIRGINIA'        => 'WV',
            'WISCONSIN'           => 'WI', 'WYOMING'              => 'WY',
            // Territories (bonus)
            'DISTRICT OF COLUMBIA' => 'DC', 'PUERTO RICO'         => 'PR',
            'GUAM'                => 'GU', 'VIRGIN ISLANDS'       => 'VI'
        };

    private static final Set<String> VALID_CODES =
        new Set<String>(NAME_TO_CODE.values());

    public static String normalize(String rawState) {
        if (String.isBlank(rawState)) return null;

        String cleaned = rawState.trim().toUpperCase();

        if (cleaned.length() == 2 && VALID_CODES.contains(cleaned)) {
            return cleaned;
        }

        if (NAME_TO_CODE.containsKey(cleaned)) {
            return NAME_TO_CODE.get(cleaned);
        }

        return null;
    }
}