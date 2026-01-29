# SPEAR - Streamlined Planning through Electronic Applications and Referrals, Victoria Scraper

* Cookie tracking - No
* Pagnation - yes, start row based via API
* Javascript - No
* Clearly defined data within a row - Partial - some data is found via details page

This is a scraper that runs on [Morph](https://morph.io). 
To get started [see the documentation](https://morph.io/documentation)

Add any issues to https://github.com/planningalerts-scrapers/issues/issues

## To run the scraper

    bundle exec ruby scraper.rb

Optionally set `MORPH_AUTHORITIES` to a comma seperated list of Authorities to examine to speed up development.

Scraper pauses between requests to be nice to the server. 

### Expected output

    Injecting configuration and compiling...
    Injecting scraper and running...
    Getting list of Authorities...
    Authenticating with SPEAR API...
    Found 81 authorities...

    Getting applications for Alpine Shire Council - Bright Office...
    Getting applications for Bass Coast Shire Council...
    Saving S262573E - 16 HAZELWOOD ROAD, SAN REMO VIC 3925 ...
    Saving S262397S - 45 RUTTLE LANE, INVERLOCH VIC 3996 ...
    Saving S262141V - HESLOP ROAD, NORTH WONTHAGGI VIC 3995 ...
    Saving S262019P - 7 MARION COURT, INVERLOCH VIC 3996 ...
    Saving S261931S - 15 STANLEY ROAD, GRANTVILLE VIC 3984 ...
    Getting applications for Baw Baw Shire Council...
    Saving S262533H - 409 COPELANDS ROAD, WARRAGUL VIC 3820 ...
    Saving S261836C - 65 ROLLO STREET, YARRAGON VIC 3823 ...
    Getting applications for Benalla Rural City Council...
    WARNING: nothing found between 28 and 60 ago! previous SPEAR record dated 2025-11-26
    ...

    Count  Authority
    -----  --------------------------------------
        0  Alpine Shire Council - Bright Office
        5  Bass Coast Shire Council
        2  Baw Baw Shire Council
           Benalla Rural City Council [Not in use since 2025-11-26]
        ...

    Finished!

Execution time: 20 to 30 minutes

## To run style and coding checks

    bundle exec rubocop

## To check for security updates

    gem install bundler-audit
    bundle-audit
