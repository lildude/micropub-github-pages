#!/usr/bin/env ruby
# Spec: https://www.w3.org/TR/micropub
require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/config_file'
require 'sinatra/content_for'
require 'uri'
require 'octokit'
require 'net/https'
require 'json'
require 'base64'
require 'open-uri'
require 'safe_yaml'
require 'liquid'
require "sinatra/reloader" if development?
require './env' if File.exists?('env.rb')

SafeYAML::OPTIONS[:default_mode] = :safe

configure { set :server, :puma }
config_file (test? ? "#{::File.dirname(__FILE__)}/test/fixtures/config.yml" : "#{::File.dirname(__FILE__)}/config.yml")

# Put helper functions in a module for easy testing.
module AppHelpers
  # https://www.w3.org/TR/micropub/#error-response
  def error(error, description = nil)
    JSON.generate({:error => error, :error_description => description })
  end

  def verify_token
    uri = URI.parse(Sinatra::Application.settings.micropub[:token_endpoint])
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.port == 443)
    request = Net::HTTP::Get.new(uri.request_uri)
    request.initialize_http_header({
      'Content-type' => 'application/x-www-form-urlencoded',
      'Authorization' => "Bearer #{@access_token}"
    })

    resp = http.request(request)
    decoded_resp = URI.decode_www_form(resp.body).each_with_object({}){|(k,v), h| h[k.to_sym] = v}
    unless (decoded_resp.include? :scope) && (decoded_resp.include? :me)
      logger.info "Received response without scope or me"
      halt 401, error('insufficient_scope', 'Insufficient scope information provided.')
    end

    decoded_resp
  end

  def publish_post(params)
    # Authenticate
    client = Octokit::Client.new(:access_token => ENV['GITHUB_ACCESS_TOKEN'])

    repo = "#{settings.github_username}/#{settings.sites[params[:site]]["github_repo"]}"

    date = DateTime.parse(params[:published])
    filename = date.strftime("%F")
    params[:slug] = create_slug(params)
    filename << "-#{params[:slug]}.md"

    logger.info "Filename: #{filename}"
    @location = "#{settings.sites[params[:site]]['site_url']}"
    @location << create_permalink(params)

    # Verify the repo exists
    halt 422, error('invalid_request', "repository #{settings.github_username}/#{settings.sites[params[:site]]['github_repo']} doesn't exit.") unless client.repository?("#{settings.github_username}/#{settings.sites[params[:site]]['github_repo']}")

    content = Liquid::Template.parse(File.read("templates/#{params[:type].to_s}.liquid")).render(params.stringify_keys)

    if client.create_contents("#{repo}", "_posts/#{filename}", "New #{params[:type].to_s}: #{filename}", content)
      status 201
      headers "Location" => "#{@location}"
      body content if ENV['RACK_ENV'] == 'test'
    end
  end

  # Download the photo and add to GitHub repo if config allows
  #
  # WARNING: the handling of alt in JSON may change in the future.
  # See https://www.w3.org/TR/micropub/#uploading-a-photo-with-alt-text
  def download_photo(params)
    # TODO: Per-repo settings take pref over global. Global only at the mo
    if settings.download_photos === true
      params[:photo].each_with_index do | photo, i |
        alt = photo.is_a?(String) ? '' : photo[:alt]
        url = photo.is_a?(String) ? photo : photo[:value]

        # TODO: Retry a few times as the file may not instantly be available for download
        begin
          begin
            sleep 2
            retries ||= 0
            file = open(url).read
            raise "Download attempt #{retries}"
          rescue
            logger.info "Download attempt #{retries}" unless ENV['RACK_ENV'] == 'test'
            retry if (retries += 1) < 5
            raise
          end

          filename = url.split('/').last

          client = Octokit::Client.new(:access_token => ENV['GITHUB_ACCESS_TOKEN'])
          repo = "#{settings.github_username}/#{settings.sites[params[:site]]["github_repo"]}"

          # Verify the repo exists
          halt 422, error('invalid_request', "repository #{settings.github_username}/#{settings.sites[params[:site]]['github_repo']} doesn't exit.") unless client.repository?("#{settings.github_username}/#{settings.sites[params[:site]]['github_repo']}")

          photo_path_prefix = settings.sites[params[:site]]['full_image_urls'] === true ? "#{settings.sites[params[:site]]['site_url']}" : ''
          photo_path = "#{photo_path_prefix}/#{settings.sites[params[:site]]['image_dir']}/#{filename}"

          # Return URL early if file already exists in the repo
          # TODO: Allow for over-writing files upon request - we'll need the SHA from this request
          begin
            client.contents("#{repo}", :path => "#{settings.sites[params[:site]]['image_dir']}/#{filename}")
          rescue Octokit::NotFound
            # Add the file if it doesn't exist
            client.create_contents("#{repo}", "#{settings.sites[params[:site]]['image_dir']}/#{filename}", "Added new photo", file)
          end
          params[:photo][i] = {'url' => photo_path, 'alt' => alt}
        rescue
          # Fall back to orig url if we can't download
          params[:photo][i] = {'url' => url, 'alt' => alt}
        end
      end
    end
    params[:photo]
  end

  # Grab the contents of the file referenced by the URL received from the client
  # This assumes the final part of the URL contains part of the filename as it
  # appears in the repository.
  def get_post(url)
    fuzzy_filename = url.split('/').last
    client = Octokit::Client.new(:access_token => ENV['GITHUB_ACCESS_TOKEN'])
    repo = "#{settings.github_username}/#{settings.sites[params[:site]]['github_repo']}"
    code = client.search_code("filename:#{fuzzy_filename} repo:#{repo}")
    # This is an ugly hack because webmock doesn't play nice - https://github.com/bblimke/webmock/issues/449
    code = JSON.parse(code, :symbolize_names => true) if ENV['RACK_ENV'] == 'test'
    content = client.contents(repo, :path => code[:items][0][:path]) if code[:total_count] == 1
    decoded_content = Base64.decode64(content[:content]).force_encoding('UTF-8').encode unless content.nil?

    jekyll_post_to_json decoded_content
  end

  def jekyll_post_to_json(content)
    # Taken from Jekyll's Jekyll::Document YAML_FRONT_MATTER_REGEXP
    if content =~ %r!\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)!m
      content = $'  # $POSTMATCH doesn't work for some reason
      front_matter = SafeYAML.load(Regexp.last_match(1))
    end

    data = {}
    data[:type] = ['h-entry'] # TODO: Handle other types.
    data[:properties] = {}
    data[:properties][:published] = [front_matter['date']]
    data[:properties][:content] = content.nil? ? [''] : [content.strip]
    data[:properties][:slug] = [front_matter['permalink']] unless front_matter['permalink'].nil?
    data[:properties][:category] = front_matter['tags'] unless front_matter['tags'].nil? || front_matter['tags'].empty?

    JSON.generate(data)
  end

  def create_slug(params)
    # Use the provided slug
    if params.include? :slug and !params[:slug].nil?
      slug = params[:slug]
    # If there's a name, use that
    elsif params.include? :name and !params[:name].nil?
      slug = slugify params[:name]
    else
    # Else generate a slug based on the published date.
      slug = DateTime.parse(params[:published]).strftime("%s").to_i % (24 * 60 * 60)
    end
    slug.to_s
  end

  def create_permalink(params)
    permalink_style = params[:permalink_style] || settings.sites[params[:site]]['permalink_style']
    date = DateTime.parse(params[:published])

    # Common Jekyll permalink template variables - https://jekyllrb.com/docs/permalinks/#template-variables
    template_variables = {
      ":year" => date.strftime("%Y"),
      ":month" => date.strftime("%m"),
      ":i_month" => date.strftime("%-m"),
      ":day" => date.strftime("%d"),
      ":i_day" => date.strftime("%-d"),
      ":short_year" => date.strftime("%y"),
      ":hour" => date.strftime("%H"),
      ":minute" => date.strftime("%M"),
      ":second" => date.strftime("%S"),
      ":title" => params[:slug],
      ":categories" => ''
    }

    permalink_style.gsub(/(:[a-z_]+)/, template_variables).gsub(/(\/\/)/, '/')
  end

  def slugify(text)
    text.downcase.gsub('/[\s.\/_]/', ' ').gsub(/[^\w\s-]/, '').squeeze(' ').tr(' ', '-').chomp('-')
  end

  # Syndicate to destinations supported by silo.pub as that's what we use
  # instead of having to implement all the APIs ourselves.
  #
  # If no destination is provided, assume it's a query and return all destinations.
  def syndicate_to(params = nil)
    # TODO: Per-repo settings take pref over global. Global only at the mo
    # TODO Add the response URL to the post meta data
    # Note: need to use Sinatra::Application.syndicate_to here until we move to
    # modular approach so the settings can be accessed when testing.
    destinations = Sinatra::Application.settings.syndicate_to.values
    clean_dests = []
    destinations.each do |e|
      clean_dests << e.select {|k| k != "silo_pub_token"}
    end
    return JSON.generate("syndicate-to": clean_dests) if params.nil?

    dest = params.key?(:"syndicate-to") ? params[:"syndicate-to"][0] : nil
    logger.info "Asked to syndicate to: #{dest}" unless ENV['RACK_ENV'] == 'test'
    return if dest.nil?

    dest_entry = destinations.find {|d| d["uid"] == dest}
    return if dest_entry.nil?

    silo_pub_token = dest_entry["silo_pub_token"]
    uri = URI.parse("https://silo.pub/micropub")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.port == 443)
    request = Net::HTTP::Post.new(uri.request_uri)
    request.initialize_http_header({
      'Authorization' => "Bearer #{silo_pub_token}"
    })

    form_data = {}
    form_data["name"] = params[:name] if params[:name]
    form_data["url"] = @location
    form_data["content"] = params[:content]

    request.set_form_data(form_data)
    resp = http.request(request)
    logger.info "Syndicated to #{dest}" unless ENV['RACK_ENV'] == 'test'
    JSON.parse(resp.body)["id_str"] if ENV['RACK_ENV'] == 'test'
  end

  # Process and clean up params for use later
  def process_params(post_params)
    # Bump off the standard Sinatra params we don't use
    post_params.reject!{ |key,_v| key =~ /^splat|captures|site/i }

    halt 400, error('invalid_request', 'Invalid request') if post_params.empty?

    # JSON-specific processing
    if env["CONTENT_TYPE"] == "application/json"
      if post_params[:type][0]
        post_params[:h] = post_params[:type][0].tr("h-",'')
        post_params.delete(:type)
      end
      post_params.merge!(post_params.delete(:properties))
      if post_params[:content]
        post_params[:content] = (post_params[:content][0].is_a? Hash) ? post_params[:content][0][:html] : post_params[:content][0]
      end
      if post_params[:name]
        post_params[:name] = post_params[:name][0]
      end
    else
      # Convert all keys to symbols from form submission
      post_params = post_params.each_with_object({}){|(k,v), h| h[k.to_sym] = v}
      post_params[:photo] = [*post_params[:photo]] if post_params[:photo]
      post_params[:"syndicate-to"] = [*post_params[:"syndicate-to"]] if post_params[:"syndicate-to"]
    end

    # Secret functionality: We may receive markdown in the content. If the first line is a header, set the name with it
    first_line = post_params[:content].match(/^#+\s?(.+$)\n+/) if post_params[:content]
    if !first_line.nil? and !post_params[:name]
      post_params[:name] = first_line[1].to_s.strip
      post_params[:content].sub!(first_line[0], '')
    end

    # Add in a few more params if they're not set
    # Spec says we should use h-entry if no type provided.
    post_params[:h] = "entry" unless post_params.include? :h
    # It's nice to honour the client's published date, if set, else set one.
    post_params[:published] = Time.now.to_s unless post_params.include? :published

    post_params
  end

  def post_type(post_params)
    if post_params[:h] == "entry"
      if post_params.include? :name
        :article
      elsif post_params.include? :in_reply_to
        :reply
      elsif post_params.include? :repost_of
        :repost
      elsif post_params.include? :bookmark_of
        :bookmark
      elsif post_params.include? :content
        :note
      else
        # Dump all params into this template as it doesn't fit any other type.
        :dump_all
      end
    elsif post_params[:h] == "event"
        :event
    elsif post_params[:h] == "cite"
        :cite
    end
  end
end

Sinatra::Application.helpers AppHelpers

# My own message for 404 errors
not_found do
  '404: Not Found'
end

before do
  # Pull out and verify the authorization header or access_token
  if env['HTTP_AUTHORIZATION']
    @access_token = env['HTTP_AUTHORIZATION'].match(/Bearer (.*)$/)[1]
  elsif params["access_token"]
    @access_token = params["access_token"]
  else
    logger.info "Received request without a token"
    halt 401, error('unauthorized')
  end

  # Remove the access_token to prevent any accidental exposure later
  params.delete("access_token")

  # Verify the token
  verify_token unless ENV['RACK_ENV'] == 'development'
end

# Query
get '/micropub/:site' do |site|
  halt 404 unless settings.sites.include? site
  halt 404 unless params.include? "q"

  case params["q"]
  when /config/
    status 200
    headers "Content-type" => "application/json"
    body JSON.generate({})  # TODO: Populate this with media-endpoint and syndicate-to when supported. Until then, empty object is fine.
  when /source/
    status 200
    headers "Content-type" => "application/json"
    #body JSON.generate("response": get_post(params[:url]))  # TODO: Determine what goes in here
    body get_post(params[:url])
  when /syndicate-to/
    status 200
    headers "Content-type" => "application/json"
    body syndicate_to
  end

end

post '/micropub/:site' do |site|
  halt 404 unless settings.sites.include? site

  # Normalise params
  post_params = env["CONTENT_TYPE"] == "application/json" ? JSON.parse(request.body.read.to_s, :symbolize_names => true) : params
  post_params = process_params(post_params)
  post_params[:site] = site

  # Check for reserved params which tell us what to do:
  # h = create entry
  # q = query the endpoint
  # action = update, delete, undelete etc.
  halt 400, error('invalid_request', "I don't know what you want me to do.") unless post_params.any? { |k, _v| [:h, :q, :action].include? k }

  # Determine the template to use based on various params received.
  post_params[:type] = post_type(post_params)

  # If there's a photo, "download" it to the GitHub repo and return the new URL
  post_params[:photo] = download_photo(post_params) if post_params[:photo]

  logger.info post_params unless ENV['RACK_ENV'] == 'test'
  # Publish the post
  publish_post post_params

  # Syndicate the post
  syndicate_to post_params
end
