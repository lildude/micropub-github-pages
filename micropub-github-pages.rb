#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/config_file'
require 'uri'
require 'net/https'
require "sinatra/reloader" if development?

config_file (test? ? "#{::File.dirname(__FILE__)}/test/fixtures/config.yml" : "#{::File.dirname(__FILE__)}/config.yml")

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
    decoded_resp = URI.decode_www_form(resp.body).inject({}) {|r, (key,value)| r[key.to_sym] = value;r}

    unless (decoded_resp.include? :scope) && (decoded_resp.include? :me)
      logger.info "Received response without scope or me"
      halt 401, "401: Unauthorized."
    end

    decoded_resp
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
  #{}"#{@result} | #{params}" if @result[:scope] == "post" && (@result[:me] == normalise_url(settings.sites[site]["site_url"]) || @result[:me] == normalise_url(settings.micropub[:token_me]))

  logger.info "#{params}" if @result[:scope] == "post"

end
