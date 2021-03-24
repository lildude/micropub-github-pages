# frozen_string_literal: true

require_relative "helpers"
# Async job to posting webmentions to Bridgy.
# The retry interval uses the agorithm as Sidekiq but we start from 1 with an initial sleep
# as you'll never get an instant publishing.
# Assuming `rand()`` always returns 30, the longest we'll be running for is just over 27 mins
class BridgyJob
  include SuckerPunch::Job
  include AppHelpers

  def perform(site, location, destination, options = {"bridgy_omit_link" => false, "bridgy_ignore_formatting" => false})
    logger.info "Syndicating #{location} to #{destination}"
    count = 1
    post_ready = false
    while count < 6
      slp = ENV["RACK_ENV"] == "test" ? 0 : (count**4) + 15 + (rand(30) * (count + 1))
      logger.info "Sleeping for #{slp}s ..."
      sleep slp
      post_ready = HTTParty.head(location, follow_redirects: true, maintain_method_across_redirects: true).success?
      break if post_ready

      count += 1
    end

    return logger.info "#{location} never appeared. No syndication attempted." unless post_ready

    resp = HTTParty.post("https://brid.gy/publish/webmention",
      body: {source: location, target: "https://brid.gy/publish/#{destination}"},
      query: options)

    return logger.info "Bridgy not happy: #{resp.code}: #{resp["error"]}" unless resp.created?

    logger.info "Successfully syndicated #{location} to #{destination}"

    # Update our post with the syndication url
    # TODO: This is a horrid hack. Find a better way of doing this when time permits
    parsed = JSON.parse(resp.body, symbolize_names: true)
    syn_url = parsed[:url]
    @site ||= site
    params = {
      url: location,
      add: {
        syndication: [syn_url]
      }
    }
    logger.info "Updating #{location} post with syndication url: #{syn_url}"

    update_post params
  end

  def settings
    Sinatra::Application.settings
  end
end
