# frozen_string_literal: true

# Async job to posting webmentions to Bridgy.
# The retry interval uses the agorithm as Sidekiq but we start from 1 with an initial sleep
# as you'll never get an instant publishing.
# Assuming `rand()`` always returns 30, the longest we'll be running for is just over 27 mins
class BridgyJob
  include SuckerPunch::Job

  def perform(location, destination, options = {"bridgy_omit_link" => false, "bridgy_ignore_formatting" => false})
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

    logger.info resp.created? ? "Successfully syndicated #{location} to #{destination}" : "Bridgy not happy: #{resp.code}: #{resp["error"]}"
  end
end
