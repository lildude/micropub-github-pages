#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/config_file'
require 'sinatra/content_for'
require 'uri'
require 'octokit'
require 'net/https'
require "sinatra/reloader" if development?

config_file (test? ? "#{::File.dirname(__FILE__)}/test/fixtures/config.yml" : "#{::File.dirname(__FILE__)}/config.yml")

require './env' if File.exists?('env.rb')

set :views, settings.root + '/templates'

helpers do
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
      halt 401, JSON.generate({:error => "insufficient_scope", :error_description => "Insufficient scope information provided."})
    end

    decoded_resp
  end

  def publish_post(site, content, params)
    # Authenticate
    client = Octokit::Client.new(:access_token => ENV['GITHUB_ACCESS_TOKEN'])

    repo = "#{settings.github_username}/#{settings.sites[site]["github_repo"]}"

    logger.info "token: #{ENV['GITHUB_ACCESS_TOKEN']} | site: #{site} | repo: #{repo}"

    date = DateTime.parse(params["published"])
    filename = date.strftime("%F")
    slug = create_slug(params)
    filename << "-#{slug}.md"

    logger.info "Filename: #{filename}"

    # Verify the repo exists
    halt 422, "422: invalid request: repository #{settings.github_username}/#{settings.sites[site]['github_repo']} doesn't exit." unless client.repository?("#{settings.github_username}/#{settings.sites[site]['github_repo']}")

    if client.create_contents("#{repo}", "_posts/#{filename}", "Added new content", content)
      status 201
      headers "Location" => "#{slug}"
      body content if ENV['RACK_ENV'] = "test"
    end
  end

  # Add trailing slash if it's missing
  def normalise_url(url)
    url << '/' unless url.end_with?('/')
    url
  end

  def create_slug(params)
    # Use the provided slug
    if params.include? "slug" and !params["slug"].nil?
      slug = params["slug"]
    # If there's a name, use that
    elsif params.include? "name" and !params["name"].nil?
      slug = slugify params["name"]
    else
    # Else generate a slug based on the published date.
      slug = DateTime.parse(params["published"]).strftime("%s").to_i % (24 * 60 * 60)
    end
    slug
  end

  def slugify(text)
    text.downcase.gsub('/[\s.\/_]/', ' ').gsub(/[^\w\s-]/, '').squeeze(' ').tr(' ', '-')
  end

  def syndicate_to(dest)
    logger.info "Syndicated to #{dest}"
  end

end

not_found do
  '404: Not Found'
end

set(:method) do |method|
  method = method.to_s.upcase
  condition { request.request_method == method }
end

before :method => :post do
  # Pull out and verify the authorization header or access_token
  if env['HTTP_AUTHORIZATION']
    auth_header = env['HTTP_AUTHORIZATION']
  elsif params[:access_token]
    auth_header = "Bearer #{params[:access_token]}"
  else
    logger.info "Received request without a token"
    halt 401, JSON.generate({:error => "unauthorized", :error_description => "Unauthorized"})
  end

  # Remove the access_token to prevent any accidental exposure later
  params.delete(:access_token)

  # Verify the token
  verify_token auth_header
end

# https://www.w3.org/TR/2016/CR-micropub-20160816/
post '/micropub/:site' do |site|
  not_found unless settings.sites.include? site

  #logger.info "#{params}" if @result[:scope] == "post"

  # Check for reserved params which tell us what to do:
  # h = create entry
  # q = query the endpoint
  # action = update, delete, undelete etc.
=begin
  if env["CONTENT_TYPE"] = "application/json"
    return 500, "500: Not implemented yet"
    params = JSON.parse(params[:body], :symbolize_keys => true)
    halt 400, "400: invalid_request" unless true
  else
=end
    halt 400, JSON.generate({:error => "invalid_request", :error_description => "I don't know what you want me to do."}) unless params.any? { |k, _v| ["h", "q", "action"].include? k }
#  end

  # Add in a few more params if they're not set
  # Spec says we should use h-entry if no type provided.
  params["h"] = "entry" unless params.include? "h"
  # It's nice to honour the client's published date, if set, else set one.
  params["published"] = Time.now.to_s unless params.include? "published"


  # Pass the content through our template, but don't output it.
  # Uses sinatra/content_for.  Alternate solution may be to use partials - http://www.sinatrarb.com/faq.html#partials or https://github.com/yb66/Sinatra-Partial

  # Convert all keys to symbols
  post_params = params.each_with_object({}){|(k,v), h| h[k.gsub(/\-/,"_").to_sym] = v}
  # Bump off params we're not interested in
  post_params.reject!{ |key,_v| key =~ /^h|splat|captures|site|mp_syndicate_to/i }

  #logger.info "#{post_params}"
  # Determine the template to use based on various params received.
  type =
    if params["h"] == "entry"
      if params.include? "name"
        :article
      elsif params.include? "in-reply-to"
        :reply
      elsif params.include? "repost-of"
        :repost
      elsif params.include? "bookmark-of"
        :bookmark
      else
        :note
      end
    elsif params["h"] == "event"
        :event
    elsif params["h"] == "cite"
        :cite
    end

  erb type, :locals => post_params

  content = erb "<%= yield_content :some_key %>"
  content

  publish_post site, content, params

  #syndicate_to params["mp-syndicate-to"] if params.include? "mp-syndicate-to"
end
