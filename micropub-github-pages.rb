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
  # TBC
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
    @auth_header = env['HTTP_AUTHORIZATION']
  elsif params[:access_token]
    @auth_header = "Bearer #{params[:access_token]}"
  else
    halt 401, "401: Unauthorized."
  end

  # Verify the token
  uri = URI.parse(settings.micropub[:token_endpoint])
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.port == 443)
  request = Net::HTTP::Get.new(uri.request_uri)
  request.initialize_http_header({
    'Content-type' => 'application/x-www-form-urlencoded',
    'Authorization' => @auth_header
  })

  resp = http.request(request)
  @decoded_resp = URI.decode_www_form(resp.body).inject({}) {|r, (key,value)| r[key.to_sym] = value;r}
end

post '/micropub/:site' do |site|
  not_found unless settings.sites.include? site
  "#{@decoded_resp}"
end
