require 'scraperwiki'
require "httparty"

# Password required to get token
BASIC_AUTH_FOR_TOKEN = "Y2xpZW50YXBwOg=="

# TODO: Only get applications that are being advertised?
def applications_page(authority_id, start_row, headers)
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

  applications["data"]["resultRows"].map do |a|
    if a["submittedDate"].nil?
      puts "SubmittedDate is empty for #{a['spearReference']}. So, skipping."
      next
    end
    {
      "council_reference" => a["spearReference"],
      "address" => a["property"],
      # TODO: Description is not terribly helpful. Probably want to get more detailed info
      "description" => a["applicationTypeDisplay"],
      # "info_url"
      "date_scraped" => Date.today.to_s,
      "date_received" => Date.strptime(a["submittedDate"], "%d/%m/%Y").to_s
    }
  end.compact
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

# For testing using a council with LOTS of applications
pp applications_page("255", 0, headers)
exit

authorities = HTTParty.post(
  "https://www.spear.land.vic.gov.au/spear/api/v1/site/search",
  body: '{"data":{"searchType":"publicsearch","searchTypeFilter":"all","searchText":null,"showInactiveSites":false}}',
  headers: headers
)

authorities["data"].each do |authority|
  puts "Getting applications for #{authority['name']}..."
  id = authority["id"]

  applications_page(id, 0, headers)
end
