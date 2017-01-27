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
require "sinatra/reloader" if development?

config_file (test? ? "#{::File.dirname(__FILE__)}/test/fixtures/config.yml" : "#{::File.dirname(__FILE__)}/config.yml")

require './env' if File.exists?('env.rb')

# TODO: I think it might be best to switch to Liquid templates instead or erb.
set :views, settings.root + '/templates'

helpers do
  # https://www.w3.org/TR/micropub/#error-response
  def error(error, description = nil)
    JSON.generate({:error => error, :error_description => description })
  end

  def verify_token(auth_header)
    uri = URI.parse(settings.micropub[:token_endpoint])
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.port == 443)
    request = Net::HTTP::Get.new(uri.request_uri)
    request.initialize_http_header({
      'Content-type' => 'application/x-www-form-urlencoded',
      'Authorization' => auth_header
    })

    resp = http.request(request)
    decoded_resp = URI.decode_www_form(resp.body).each_with_object({}){|(k,v), h| h[k.to_sym] = v}
    unless (decoded_resp.include? :scope) && (decoded_resp.include? :me)
      logger.info "Received response without scope or me"
      halt 401, error('insufficient_scope', 'Insufficient scope information provided.')
    end

    decoded_resp
  end

  def publish_post(site, content, params)
    # Authenticate
    client = Octokit::Client.new(:access_token => ENV['GITHUB_ACCESS_TOKEN'])

    repo = "#{settings.github_username}/#{settings.sites[site]["github_repo"]}"

    logger.info "token: #{ENV['GITHUB_ACCESS_TOKEN']} | site: #{site} | repo: #{repo}"

    date = DateTime.parse(params[:published])
    filename = date.strftime("%F")
    params[:slug] = create_slug(params)
    filename << "-#{params[:slug]}.md"

    logger.info "Filename: #{filename}"
    location = create_permalink(site, params)

    # Verify the repo exists
    halt 422, error('invalid_request', "repository #{settings.github_username}/#{settings.sites[site]['github_repo']} doesn't exit.") unless client.repository?("#{settings.github_username}/#{settings.sites[site]['github_repo']}")

    if client.create_contents("#{repo}", "_posts/#{filename}", "Added new content", content)
      status 201
      headers "Location" => "#{location}"
      body content if ENV['RACK_ENV'] = "test"
    end
  end

  # Download the photo and add to GitHub repo if config allows
  def download_photo(site, photo)
    # TODO: Per-repo settings take pref over global. Global only at the mo
    if settings.download_photos === true
      file = open(photo).read
      filename = photo.split('/').last

      client = Octokit::Client.new(:access_token => ENV['GITHUB_ACCESS_TOKEN'])
      repo = "#{settings.github_username}/#{settings.sites[site]["github_repo"]}"

      # Verify the repo exists
      halt 422, error('invalid_request', "repository #{settings.github_username}/#{settings.sites[site]['github_repo']} doesn't exit.") unless client.repository?("#{settings.github_username}/#{settings.sites[site]['github_repo']}")

      photo_path_prefix = settings.sites[site]['full_image_urls'] === true ? "#{settings.sites[site]['site_url']}" : ''
      photo_path = "#{photo_path_prefix}/#{settings.sites[site]['image_dir']}/#{filename}"

      # Return URL early if file already exists in the repo
      # TODO: Allow for over-writing files upon request - we'll need the SHA from this request
      return photo_path if client.contents("#{repo}", :path => "#{settings.sites[site]['image_dir']}/#{filename}") rescue nil

      client.create_contents("#{repo}", "#{settings.sites[site]['image_dir']}/#{filename}", "Added new photo", file)
      photo = photo_path
    end
    photo
  end

  # Add trailing slash if it's missing
  def normalise_url(url)
    url << '/' unless url.end_with?('/')
    url
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
    slug
  end

  def create_permalink(site, params)
    permalink_style = settings.sites[site]['permalink_style']
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

    permalink_style.gsub(/(:[a-z]+)/, template_variables).gsub(/(\/\/)/, '/')
  end

  def slugify(text)
    text.downcase.gsub('/[\s.\/_]/', ' ').gsub(/[^\w\s-]/, '').squeeze(' ').tr(' ', '-')
  end

  def syndicate_to(dest)
    logger.info "Syndicated to #{dest}"
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
      post_params[:content] = post_params[:content][0]
      post_params[:photo] = post_params[:photo][0] if post_params[:photo].is_a? Array and post_params[:photo].length == 1 and post_params[:photo][0].is_a? String
    else
      # Convert all keys to symbols from form submission
      post_params = post_params.each_with_object({}){|(k,v), h| h[k.gsub(/\-/,"_").to_sym] = v}
    end

    # Secret functionality: We may receive markdown in the content. If the first line is a header, set the name with it
    first_line = post_params[:content].match(/^#+\s?(.+$)\n+/)
    if !first_line.nil? and !post_params[:name]
      post_params[:name] = first_line[1].to_s
      post_params[:content].sub!(first_line[0], '')
    end

    # Add in a few more params if they're not set
    # Spec says we should use h-entry if no type provided.
    post_params[:h] = "entry" unless post_params.include? :h
    # It's nice to honour the client's published date, if set, else set one.
    post_params[:published] = Time.now.to_s unless post_params.include? :published

    #p "#{post_params}"
    post_params

  end
end

# My own message for 404 errors
not_found do
  '404: Not Found'
end

before do
  # Pull out and verify the authorization header or access_token
  if env['HTTP_AUTHORIZATION']
    auth_header = env['HTTP_AUTHORIZATION']
  elsif params["access_token"]
    auth_header = "Bearer #{params["access_token"]}"
  else
    logger.info "Received request without a token"
    halt 401, error('unauthorized')
  end

  # Remove the access_token to prevent any accidental exposure later
  params.delete("access_token")

  # Verify the token
  verify_token auth_header
end

# Query
get '/micropub/:site' do |site|
  halt 404 unless settings.sites.include? site
  halt 404 unless params.include? "q"

  case params["q"]
  when /config/
    status 200
    headers "Content-type" => "application/json"
    body JSON.generate({})  # TODO: Determine what goes in here
  when /source/
    status 200
    headers "Content-type" => "application/json"
    body JSON.generate({})  # TODO: Determine what goes in here
  when /syndicate-to/
    status 200
    headers "Content-type" => "application/json"
    body JSON.generate("syndicate-to": [{}])  # TODO: Determine what goes in here
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
  type =
    if post_params[:h] == "entry"
      if post_params.include? :name
        :article
      elsif post_params.include? :in_reply_to
        :reply
      elsif post_params.include? :repost_of
        :repost
      elsif post_params.include? :bookmark_of
        :bookmark
      else
        :note
      end
    elsif post_params[:h] == "event"
        :event
    elsif post_params[:h] == "cite"
        :cite
    end

  # If there's a photo, "download" it to the GitHub repo and return the new URL
  # TODO: Use the config to return a complete URL.
  post_params[:photo] = download_photo(site, post_params[:photo]) if post_params[:photo]

  erb type, :locals => post_params

  content = erb "<%= yield_content :some_key %>"
  content

  publish_post site, content, post_params

  #syndicate_to post_params["mp-syndicate-to"] if post_params.include? "mp-syndicate-to"
end
