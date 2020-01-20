require 'scraperwiki'
# Migrated this scraper from https://github.com/openaustralia/planningalerts-parsers/blob/master/lib/spear_scraper.rb

require 'mechanize'
require 'json'

# Extracts all the data on a single page of results
def extract_page_data(data)
  comment_url = "https://www.spear.land.vic.gov.au/spear/pages/public-and-other-users/objectors.shtml"

  apps = []
  # Skip first two row (header) and last row (page navigation)


  JSON.parse(data)["resultRows"].each do |row|
    
    # Type appears to be either something like "Certification of a Plan" or "Planning Permit and Certification"
    # I think we need to look in detail at the application to get the description
    # TODO: Figure out whether we should ignore "Certification of a Plan"
    #type = values[3].inner_html.strip
    #status = values[4].inner_html.strip
    # I'm going to take a punt here on what the correct thing to do is - I think if there is a link available to
    # the individual planning application that means that it's something that requires deliberation and so interesting.
    # I'm going to assume that everything else is purely "procedural" and should not be recorded here

    # If there is a link on the address record this development application
    
      info_url = "https://www.spear.land.vic.gov.au/spear/applicationDetails/RetrievePublicApplication.do?cacheApplicationListContext=true&spearNum=#{row['spearReference']}"
      # puts row.to_yaml
      record = {
        # We're using the SPEAR Ref # because we want that to be unique across the "authority"
        'council_reference' => row['spearReference'],
        'address' => row['property'],
        'info_url' => info_url,
        'comment_url' => comment_url,
        'date_scraped' => Date.today.to_s
      }
      if row['submittedDate']
        record['date_received'] = Date.strptime(row['submittedDate'], "%d/%m/%Y").to_s
      end

      # Get more detailed information by going to the application detail page (but only if necessary)
      record["description"] = extract_description(info_url)
      if record["description"] == "" 
        record["description"] = row["applicationTypeDisplay"]
      end
      #p record
      ScraperWiki.save_sqlite(['council_reference'], record)

  end
end

# Get a description of the application extracted from the more detailed information page (at info_url)
def extract_description(info_url)
  agent = Mechanize.new
  agent.verify_mode = OpenSSL::SSL::VERIFY_NONE

  page = agent.get(info_url)

  # The horrible thing about this page is they use tables for layout. Well done!
  # Also I think the "Intended use" bit looks like the most useful. So, we'll use that for the description
  table = page.at('div#bodypadding table')
  # For some reason occasionaly this page can be entirely blank. If it is just do our best and continue
  if table
    row = table.search('table')[1].search('tr').find do |row|
      # <th> tag contains the name of the field, <td> tag contains its value
      row.at('th') && row.at('th').inner_text.strip == "Intended use"
    end
    row.at('td').inner_text.strip if row
  end
end

def applications(web_form_name)
  url = "http://www.spear.land.vic.gov.au/spear/publicSearch/Search.do"

  agent = Mechanize.new
  # Doing this as a workaround because there don't appear to be root certificates for Ruby 1.9 installed on
  # Scraperwiki. Doesn't really make any difference because we're not sending anything requiring any kind
  # of security back and forth
  agent.verify_mode = OpenSSL::SSL::VERIFY_NONE

  page = agent.get(url)
  form = page.forms.first
  # TODO: Is there a more sensible way to pick the item in the drop-down?
  form.field_with(:name => "councilName").options.find{|o| o.text == web_form_name}.click
  page = form.submit
   
  response = agent.post("https://www.spear.land.vic.gov.au/spear/resources/applicationlist/publicSearch", '{"applicationListSearchRequest":{"searchFilters":[],"searchText":null,"myApplications":false,"watchedApplications":false,"searchInitiatedByUserClickEvent":false,"sortField":"SPEAR_REF","sortDirection":"desc","startRow":0},"tab":"ALL"}', {'Content-Type' => 'application/json'})
  extract_page_data(response.body)

end

url = "http://www.spear.land.vic.gov.au/spear/publicSearch/Search.do"

agent = Mechanize.new
agent.verify_mode = OpenSSL::SSL::VERIFY_NONE

page = agent.get(url)
form = page.forms.first
council_names = form.field_with(:name => "councilName").options.map{|o| o.text}[1..-1]

council_names.each do |council_name|
  puts "Scraping #{council_name}..."
  applications(council_name)
end

