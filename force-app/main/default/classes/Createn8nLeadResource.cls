@RestResource(urlMapping='/n8nLead/*')
global class Createn8nLeadResource {

    private static Map<String, String> STATE_MAP = new Map<String, String>{
        'alabama' => 'AL', 'alaska' => 'AK', 'arizona' => 'AZ',
        'arkansas' => 'AR', 'california' => 'CA', 'colorado' => 'CO',
        'connecticut' => 'CT', 'delaware' => 'DE', 'florida' => 'FL',
        'georgia' => 'GA', 'hawaii' => 'HI', 'idaho' => 'ID',
        'illinois' => 'IL', 'indiana' => 'IN', 'iowa' => 'IA',
        'kansas' => 'KS', 'kentucky' => 'KY', 'louisiana' => 'LA',
        'maine' => 'ME', 'maryland' => 'MD', 'massachusetts' => 'MA',
        'michigan' => 'MI', 'minnesota' => 'MN', 'mississippi' => 'MS',
        'missouri' => 'MO', 'montana' => 'MT', 'nebraska' => 'NE',
        'nevada' => 'NV', 'new hampshire' => 'NH', 'new jersey' => 'NJ',
        'new mexico' => 'NM', 'new york' => 'NY', 'north carolina' => 'NC',
        'north dakota' => 'ND', 'ohio' => 'OH', 'oklahoma' => 'OK',
        'oregon' => 'OR', 'pennsylvania' => 'PA', 'rhode island' => 'RI',
        'south carolina' => 'SC', 'south dakota' => 'SD', 'tennessee' => 'TN',
        'texas' => 'TX', 'utah' => 'UT', 'vermont' => 'VT',
        'virginia' => 'VA', 'washington' => 'WA', 'west virginia' => 'WV',
        'wisconsin' => 'WI', 'wyoming' => 'WY', 'district of columbia' => 'DC',
        'washington dc' => 'DC', 'washington d.c.' => 'DC'
    };

    private static String toStateCode(String raw) {
        if (raw == null || raw.trim() == '') {
            return '';
        }
        String s = raw.trim();

        // If purely numeric → it's a zip code, not a state
        if (s.isNumeric()) {
            return '';
        }

        if (s.length() == 2) {
            return s.toUpperCase();
        }
        String code = STATE_MAP.get(s.toLowerCase());
        if (code != null) {
            return code;
        }
        return s;
    }

    @HttpPost
    global static ResponseWrapper createLead() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        ResponseWrapper result = new ResponseWrapper();

        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            system.debug('Incoming body >> ' + body);

            // ── Name splitting ───────────────────────────────────────────
            String fullName  = (String) body.get('to');
            String firstName = '';
            String lastName  = '';
            if (fullName != null && fullName.contains(' ')) {
                List<String> nameParts = fullName.trim().split(' ');
                firstName = nameParts[0];
                nameParts.remove(0);
                lastName = String.join(nameParts, ' ');
            } else {
                lastName = fullName != null ? fullName : '';
            }

            String address    = (String) body.get('Address');
            String street     = '';
            String city       = '';
            String stateCode  = '';
            String postalCode = '';

            if (address != null && address.trim() != '') {
                List<String> parts = address.split(',');

                // Part 0 → Street
                if (parts.size() > 0) {
                    street = parts[0].trim();
                }

                // Part 1 → City
                if (parts.size() > 1) {
                    city = parts[1].trim();
                }

                if (parts.size() == 3) {
                    String segment = parts[2].trim();

                    if (segment.contains(' ')) {
                        // e.g. "NY 10001" or "New York 10001"
                        List<String> stateZip = segment.split('\\s+');
                        String sp1 = stateZip[0].trim();
                        String sp2 = stateZip.size() > 1 ? stateZip[1].trim() : '';

                        if (sp1.isNumeric()) {
                            // "10001 NY" — unlikely but safe
                            postalCode = sp1;
                            stateCode  = toStateCode(sp2);
                        } else if (sp2.isNumeric()) {
                            // "NY 10001" — most common
                            stateCode  = toStateCode(sp1);
                            postalCode = sp2;
                        } else {
                           
                            stateCode = toStateCode(sp1);
                        }

                    } else if (segment.isNumeric()) {
                      
                        postalCode = segment;
                        stateCode  = ''; 

                    } else {
                        // State only, no zip
                        stateCode = toStateCode(segment);
                    }

                } else if (parts.size() >= 4) {
                    // "Street, City, State, Zip"
                    String statePart = parts[2].trim();
                    String zipPart   = parts[3].trim();

                    stateCode  = statePart.isNumeric() ? '' : toStateCode(statePart);
                    postalCode = zipPart.isNumeric()   ? zipPart : '';
                }
            }

            system.debug('Parsed Street >> ' + street);
            system.debug('Parsed City   >> ' + city);
            system.debug('Parsed State  >> ' + stateCode);
            system.debug('Parsed Zip    >> ' + postalCode);

            // ── DOB parsing ──────────────────────────────────────────────
            String dobStr = (String) body.get('DOB');
            Date dob = null;
            if (dobStr != null) {
                dobStr = dobStr.replaceAll('(?i)(\\d+)(st|nd|rd|th)', '$1').trim();
                Map<String, String> monthMap = new Map<String, String>{
                    'january' => '01', 'february' => '02', 'march' => '03',
                    'april' => '04', 'may' => '05', 'june' => '06',
                    'july' => '07', 'august' => '08', 'september' => '09',
                    'october' => '10', 'november' => '11', 'december' => '12'
                };
                try {
                    String day;
                    String month;
                    String year;

                    if (dobStr.contains('-') && dobStr.length() == 10) {
                        // Format: "2000-08-19"
                        dob = Date.valueOf(dobStr);

                    } else if (dobStr.contains('/')) {
                        // Format: "08/19/2000"
                        List<String> dp = dobStr.split('/');
                        month = dp[0].trim().leftPad(2, '0');
                        day   = dp[1].trim().leftPad(2, '0');
                        year  = dp[2].trim();
                        dob   = Date.valueOf(year + '-' + month + '-' + day);

                    } else if (dobStr.contains(',')) {
                        // Format: "August 19, 2000"
                        dobStr = dobStr.replace(',', '');
                        List<String> dp = dobStr.split(' ');
                        month = monthMap.get(dp[0].trim().toLowerCase());
                        day   = String.valueOf(Integer.valueOf(dp[1].trim())).leftPad(2, '0');
                        year  = dp[2].trim();
                        if (month != null) {
                            dob = Date.valueOf(year + '-' + month + '-' + day);
                        }

                    } else {
                        // Format: "19 August 2000" or "August 19 2000"
                        List<String> dp = dobStr.split(' ');
                        if (dp.size() == 3) {
                            if (dp[0].isNumeric()) {
                                day   = String.valueOf(Integer.valueOf(dp[0].trim())).leftPad(2, '0');
                                month = monthMap.get(dp[1].trim().toLowerCase());
                                year  = dp[2].trim();
                            } else {
                                month = monthMap.get(dp[0].trim().toLowerCase());
                                day   = String.valueOf(Integer.valueOf(dp[1].trim())).leftPad(2, '0');
                                year  = dp[2].trim();
                            }
                            if (month != null) {
                                dob = Date.valueOf(year + '-' + month + '-' + day);
                            }
                        }
                    }
                } catch (Exception dobEx) {
                    system.debug('DOB parsing failed: ' + dobEx.getMessage());
                }
            }

            // ── Create Lead ──────────────────────────────────────────────
            Lead ld = new Lead();
            ld.FirstName   = firstName;
            ld.LastName    = lastName;
            ld.MobilePhone = (String) body.get('Caller_Id');
            ld.Phone       = (String) body.get('Caller_Id');
            ld.Company     = 'BatonCare';
            ld.Street      = street;
            ld.City        = city;
            ld.StateCode   = stateCode;
            ld.PostalCode  = postalCode;
            ld.CountryCode = 'US';
            ld.Status      = 'New';
            if (dob != null) {
                ld.Date_of_Birth__c = dob;
            }
            insert ld;

            result.success = true;
            result.id      = ld.Id;
            result.message = 'Lead created successfully';
            res.statusCode = 201;

        } catch (Exception e) {
            result.success = false;
            result.error   = e.getMessage();
            res.statusCode = 400;
        }

        return result;
    }

    global class ResponseWrapper {
        global Boolean success;
        global String id;
        global String message;
        global String error;
    }
}