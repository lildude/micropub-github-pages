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
      halt 401, "401: Unauthorized."
    end

    decoded_resp
  end

  def publish_post(site, content, params)
    # Authenticate
    client = Octokit::Client.new(:access_token => ENV['GITHUB_ACCESS_TOKEN'])

    repo = "#{settings.github_username}/#{settings.sites[site]["github_repo"]}"

    logger.info "token: #{ENV['GITHUB_ACCESS_TOKEN']} | site: #{site} | repo: #{repo}"

    # Verify the repo exists
    halt 422, "422: invalid request: repository #{settings.github_username}/#{settings.sites[site]['github_repo']} doesn't exit." unless client.repository?("#{settings.github_username}/#{settings.sites[site]['github_repo']}")

    now = Time.now
    date = now.strftime("%F")

    filename = params["published"].strftime("%F")
    filename << "-#{create_slug(params)}.md"

    logger.info "Filename: #{filename}"
    if client.create_contents("#{repo}", "_posts/#{filename}", "Added new content", content)
      "_posts/#{filename}.md successfully created."
    end
  end

  # Add trailing slash if it's missing
  def normalise_url(url)
    url << '/' unless url.end_with?('/')
    url
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
    halt 401, "401: Unauthorized."
  end

  # Verify the token
  @result = verify_token auth_header

end

post '/micropub/:site' do |site|
  not_found unless settings.sites.include? site

  #logger.info "#{params}" if @result[:scope] == "post"

  # Add in a few more params if they're not set
  params["published"] = Time.now unless params.include? "published"

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
end
