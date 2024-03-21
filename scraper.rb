require 'scraperwiki'
require "httparty"

# Password required to get token
BASIC_AUTH_FOR_TOKEN = "Y2xpZW50YXBwOg=="

def applications_page(authority_id, start_row, headers)
  # Getting the most recently submitted applications for the particular authority
  query = {
    "data": {
      "applicationListSearchRequest": {
        "searchFilters": [
          {
            "id": "completed",
            "selected": ["ALL"]
          }
        ],
        "searchText": nil,
        "myApplications": false,
        "watchedApplications": false,
        "searchInitiatedByUserClickEvent": false,
        "sortField": "SUBMITTED_DATE",
        "sortDirection": "desc",
        "startRow": start_row
      },
      "tab": "ALL",
      "filterString": "",
      "completedFilterString": "ALL",
      "responsibleAuthoritySiteId": authority_id,
    }
  }

  applications = HTTParty.post(
    "https://www.spear.land.vic.gov.au/spear/api/v1/applicationlist/publicSearch",
    body: query.to_json,
    headers: headers
  )

  applications["data"]["resultRows"].each do |a|
    if a["submittedDate"].nil?
      puts "SubmittedDate is empty for #{a['spearReference']}. So, skipping."
      next
    end

    # We need to get more detailed information to get the application id (for
    # the info_url) and a half-way decent description
    # This requires two more API calls. Ugh.

    result = HTTParty.get(
      "https://www.spear.land.vic.gov.au/spear/api/v1/applications/retrieve/#{a['spearReference']}?publicView=true",
      headers: headers
    )
    application_id = result["data"]["applicationId"]

    detail = HTTParty.get(
      "https://www.spear.land.vic.gov.au/spear/api/v1/applications/#{application_id}/summary?publicView=true",
      headers: headers
    )
    if detail && detail["data"] 
      yield(
        "council_reference" => a["spearReference"],
        "address" => a["property"],
        "description" => detail["data"]["intendedUse"].to_s, # Converts nil to an empty string - avoid type mismatch
        "info_url" => "https://www.spear.land.vic.gov.au/spear/app/public/applications/#{application_id}/summary",
        "date_scraped" => Date.today.to_s,
        "date_received" => Date.strptime(a["submittedDate"], "%d/%m/%Y").to_s
      )
    else
      puts "Skipping #{a['spearReference']} due to missing detail data."
end

  [applications["data"]["resultRows"].count, applications["data"]["numFound"]]
end

def all_applications(authority_id, headers)
  start_row = 0

  loop do
    number_on_page, total_no = applications_page(authority_id, start_row, headers) do |record|
      yield record
    end
    start_row += number_on_page
    break if start_row >= total_no
  end
end

tokens = HTTParty.post(
  "https://www.spear.land.vic.gov.au/spear/api/v1/oauth/token",
  body: "username=public&password=&grant_type=password&client_id=clientapp&scope=spear_rest_api",
  headers: { "Authorization" => "Basic #{BASIC_AUTH_FOR_TOKEN}"}
)

headers = {
  "Authorization" => "Bearer #{tokens['access_token']}",
  "Content-Type" => "application/json"
}

authorities = HTTParty.post(
  "https://www.spear.land.vic.gov.au/spear/api/v1/site/search",
  body: '{"data":{"searchType":"publicsearch","searchTypeFilter":"all","searchText":null,"showInactiveSites":false}}',
  headers: headers
)

authorities["data"].each do |authority|
  puts "Getting applications for #{authority['name']}..."
  id = authority["id"]

  all_applications(id, headers) do |record|
    # We only want the last 28 days
    break if Date.parse(record["date_received"]) < Date.today - 28

    puts "Saving #{record['council_reference']}..."
    ScraperWiki.save_sqlite(["council_reference"], record)
  end
end
