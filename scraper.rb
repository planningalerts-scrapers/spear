require 'scraperwiki'
require "httparty"

# Password required to get token
BASIC_AUTH_FOR_TOKEN = "Y2xpZW50YXBwOg=="

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
        "sortField": "SPEAR_REF",
        "sortDirection": "desc",
        "startRow": 0
      },
      "tab": "ALL",
      "filterString": "",
      "completedFilterString": "ALL",
      "responsibleAuthoritySiteId": id
    }
  }

  applications = HTTParty.post(
    "https://www.spear.land.vic.gov.au/spear/api/v1/applicationlist/publicSearch",
    body: query.to_json,
    headers: headers
  )
  pp applications
  exit
end
