#!/usr/bin/env ruby
# frozen_string_literal: true

require "scraperwiki"
require "httparty"
require "yaml"

class Scraper
  # Password required to get token
  BASIC_AUTH_FOR_TOKEN = "Y2xpZW50YXBwOg=="
  DAYS_WARNING = 270  # 9 months - small rural councils will see few subdivisions
  AUTH_TIMEOUT = 600 # 10 minutes in seconds (conservative)
  STATE_PLANNING_MINISTER = "Minister for Planning" # historical?

  # Throttle block to be nice to servers we are scraping
  def throttle_block(extra_delay: 0.5)
    if @pause_duration
      puts "  Pausing #{@pause_duration}s" if ENV["DEBUG"] || ENV["MORPH_DEBUG"]
      sleep(@pause_duration)
    end
    start_time = Time.now.to_f
    page = yield
    @pause_duration = (Time.now.to_f - start_time + extra_delay).round(3)
    page
  end

  # Cleanup and vacuum database of old records (planning alerts only looks at last 5 days)
  def cleanup_old_records
    cutoff_date = (Date.today - 30).to_s
    vacuum_cutoff_date = (Date.today - 35).to_s

    stats = ScraperWiki.sqliteexecute(
      "SELECT COUNT(*) as count, MIN(date_scraped) as oldest FROM data WHERE date_scraped < ?",
      [cutoff_date]
    ).first

    deleted_count = stats["count"]
    oldest_date = stats["oldest"]

    return unless deleted_count.positive? || ENV["VACUUM"]

    puts "Deleting #{deleted_count} applications scraped between #{oldest_date} and #{cutoff_date}"
    ScraperWiki.sqliteexecute("DELETE FROM data WHERE date_scraped < ?", [cutoff_date])

    # VACUUM roughly once each 33 days, or if older than 35 days (first time), or if VACUUM is set
    return unless rand < 0.03 || (oldest_date && oldest_date < vacuum_cutoff_date) || ENV["VACUUM"]

    puts "  Running VACUUM to reclaim space..."
    ScraperWiki.sqliteexecute("VACUUM")
  end

  def applications_page(authority_id, start_row)
    # Getting the most recently submitted applications for the particular authority
    query = {
      "data": {
        "applicationListSearchRequest": {
          "searchFilters": [
            {
              "id": "completed",
              "selected": ["ALL"],
            },
          ],
          "searchText": nil,
          "myApplications": false,
          "watchedApplications": false,
          "searchInitiatedByUserClickEvent": false,
          "sortField": "SUBMITTED_DATE",
          "sortDirection": "desc",
          "startRow": start_row,
        },
        "tab": "ALL",
        "filterString": "",
        "completedFilterString": "ALL",
        "responsibleAuthoritySiteId": authority_id,
      },
    }

    application_list_url = "https://www.spear.land.vic.gov.au/spear/api/v1/applicationlist/publicSearch"
    applications = throttle_block do
      HTTParty.post(
        application_list_url,
        body: query.to_json,
        headers: headers
      )
    end

    # Process a page of applications
    rows = applications&.dig("data", "resultRows")
    if rows.nil?
      puts "ERROR: unable to find rows from #{application_list_url} - aborting this authority"
      puts "DOM element: #{applications.inspect}" if ENV["DEBUG"]
      return [0, 0]
    end

    number_on_page = rows.size
    total_no = applications&.dig("data", "numFound").to_i
    if ENV["DEBUG"]
      puts "Found #{number_on_page} rows, starting from #{start_row} out of #{total_no - start_row} left of applications from #{application_list_url}"
    end

    rows.each do |a|
      spear_reference = a["spearReference"]
      if spear_reference.nil?
        puts "ERROR: spear_reference is empty - skipping record from #{application_list_url}"
        puts "DOM element: #{a.inspect}" if ENV["DEBUG"]
        next
      end

      if a["submittedDate"].nil?
        puts "ERROR: SubmittedDate is empty for #{spear_reference} - skipping record from #{application_list_url}"
        puts "DOM element: #{a.inspect}" if ENV["DEBUG"]
        next
      end

      # We need to get more detailed information to get the application id (for the info_url) and
      # a half-way decent description.
      # This requires two more API calls. Ugh.
      application_url = "https://www.spear.land.vic.gov.au/spear/api/v1/applications/retrieve/#{spear_reference}?publicView=true"
      result = throttle_block do
        HTTParty.get(
          application_url,
          headers: headers
        )
      end
      application_id = result["data"]&.dig("applicationId")
      if application_id.nil?
        puts "ERROR: Missing application_id for #{spear_reference} - skipping record from #{application_url}"
        puts "HTTParty response: #{result.inspect}" if ENV["DEBUG"]
        next
      end
      detail_url = "https://www.spear.land.vic.gov.au/spear/api/v1/applications/#{application_id}/summary?publicView=true"
      detail = throttle_block do
        HTTParty.get(
          detail_url,
          headers: headers
        )
      end

      unless detail&.dig("data")
        puts "ERROR: Missing detail data for #{spear_reference} - skipping record from #{detail_url}"
        puts "HTTParty response: #{detail.inspect}" if ENV["DEBUG"]
        next
      end

      description = detail&.dig("data", "intendedUse").to_s
      if description.empty?
        if ENV['DEBUG']
          puts "NOTE: Missing Intended Use for #{spear_reference}, using Proposal Type and Application Type instead for description"
        end
        # puts "HTTParty response: #{detail.to_yaml}" if ENV['DEBUG']
        description = [
          detail&.dig("data", "appDisplayName"),
          detail&.dig("data", "propsalTypeDisplay"),
        ].flatten.compact.join(".\n")
      end
      if description.empty?
        puts "WARNING: missing description for #{spear_reference} - from #{detail_url}"
        puts "HTTParty response: #{detail.inspect}" if ENV["DEBUG"]
      end

      yield(
        "council_reference" => a["spearReference"],
          "address" => a["property"],
          "description" => description,
          "info_url" => "https://www.spear.land.vic.gov.au/spear/app/public/applications/#{application_id}/summary",
          "date_scraped" => Date.today.to_s,
          "date_received" => Date.strptime(a["submittedDate"], "%d/%m/%Y").to_s
      )
    end
    [number_on_page, total_no]
  end

  def all_applications(authority_id, &block)
    start_row = 0

    loop do
      puts "  Getting row #{start_row} onwards for #{authority_id}..." if ENV["DEBUG"]
      number_on_page, total_no = applications_page(authority_id, start_row, &block)
      puts "  Found #{number_on_page} applications from #{authority_id}, total no = #{total_no}" if ENV["DEBUG"]
      start_row += number_on_page
      break if start_row >= total_no
    end
    puts "ERROR: Expected to find at least old applications for authority!"
  end

  def run
    puts "Getting list of Authorities..."
    authorities = throttle_block do
      HTTParty.post(
        "https://www.spear.land.vic.gov.au/spear/api/v1/site/search",
        body: '{"data":{"searchType":"publicsearch","searchTypeFilter":"all","searchText":null,"showInactiveSites":false}}',
        headers: headers
      )
    end

    puts "Found #{authorities['data'].size} authorities..."
    counts = {}
    most_recent_entry = {}
    authorities["data"].each do |authority|
      next if ENV["MORPH_AUTHORITIES"] && !ENV["MORPH_AUTHORITIES"].split(",").include?(authority["name"])

      puts "Getting applications for #{authority['name']}..."
      id = authority["id"]

      all_applications(id) do |record|
        date_received = Date.parse(record["date_received"])
        most_recent_entry[authority["name"]] ||= date_received
        if date_received < Date.today - DAYS_WARNING && !authority["name"].include?(STATE_PLANNING_MINISTER)
          puts "WARNING: nothing found between 28 and #{DAYS_WARNING} days ago! previous SPEAR record dated #{record['date_received']}"
        else
          counts[authority["name"]] ||= 0
        end
        # We only want the last 28 days
        if date_received < Date.today - 28
          puts "  Ignoring remaining rows received #{record['date_received']} and earlier ..." if ENV['DEBUG']
          break
        end

        puts "Saving #{record['council_reference']} - #{record['address']}"
        puts record.to_yaml, "" if ENV["DEBUG"]
        counts[authority["name"]] += 1
        ScraperWiki.save_sqlite(["council_reference"], record)
      end
    end
    puts
    puts "Count  Authority"
    puts "-----  --------------------------------------"
    authorities["data"].each do |authority|
      name = authority["name"]
      if name.include? STATE_PLANNING_MINISTER
        puts "#{counts[name] ? format('%5d', counts[name]) : '  N/A'}  #{name}"
      else
        puts "#{counts[name] ? format('%5d', counts[name]) : '     '}  #{name}#{counts[name] ? '' : " [Not in use since #{most_recent_entry[name] || 'forever'}]"}"
      end
    end
    puts
    cleanup_old_records
    puts "Finished!"
  end

  def headers
    if @token_expires_at.nil? || Time.now >= @token_expires_at
      refresh_token
    end

    {
      "Authorization" => "Bearer #{@access_token}",
      "Content-Type" => "application/json"
    }
  end

  private

  def refresh_token
    puts "Authenticating with SPEAR API..."
    tokens = throttle_block do
      HTTParty.post(
        "https://www.spear.land.vic.gov.au/spear/api/v1/oauth/token",
        body: "username=public&password=&grant_type=password&client_id=clientapp&scope=spear_rest_api",
        headers: { "Authorization" => "Basic #{BASIC_AUTH_FOR_TOKEN}" }
      )
    end

    @access_token = tokens['access_token']
    # Set expiry - using 15 minutes to be conservative (you mentioned ~20 min actual)
    @token_expires_at = Time.now + AUTH_TIMEOUT
  end
end

Scraper.new.run if __FILE__ == $PROGRAM_NAME
