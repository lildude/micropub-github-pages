# frozen_string_literal: true

require 'sinatra'
require 'sinatra/config_file'
# require 'uri'
require 'octokit'
require 'httparty'
require 'json'
require 'base64'
# require 'open-uri'
require 'safe_yaml'
require 'liquid'
require 'securerandom'
require 'stringex'
require_relative 'lib/helpers'
require 'sinatra/reloader' if development?
require './env' if File.exist?('env.rb')

SafeYAML::OPTIONS[:default_mode] = :safe

configure { set :server, :puma }

config_yml = test? ? "#{File.dirname(__FILE__)}/test/fixtures/config.yml" : "#{File.dirname(__FILE__)}/config.yml"

# Override config file if CONFIG env var is set
if ENV['SITES_CONFIG'] && !ENV['SITES_CONFIG'].empty?
  logger.info 'Using configuration from SITES_CONFIG'
  config_yml = Tempfile.new(['config-', '.yml'])
  File.write(config_yml, JSON.parse(ENV['SITES_CONFIG']).to_yaml)
end

config_file config_yml

# Default settings if not set in config
configure { set download_photos: false } unless settings.respond_to?(:download_photos)
configure { set syndicate_to: {} } unless settings.respond_to?(:syndicate_to)

Sinatra::Application.helpers AppHelpers

# My own message for 404 errors
not_found do
  '404: Not Found'
end

before do
  # Pull out and verify the authorization header or access_token
  if env['HTTP_AUTHORIZATION']
    @access_token = env['HTTP_AUTHORIZATION'].match(/Bearer (.*)$/)[1]
  elsif params['access_token']
    @access_token = params['access_token']
  else
    logger.info 'Received request without a token'
    error('unauthorized')
  end

  # Remove the access_token to prevent any accidental exposure later
  params.delete('access_token')

  # Verify the token and extract scopes
  @scopes = verify_token
end

# Multiple site query
get '/micropub' do
  halt 404 unless params.include? 'q'
  if params['q'] == 'config'
    status 200
    headers 'Content-type' => 'application/json'
    config = {}
    config['destination'] = []
    settings.sites.each do |site, opts|
      config['destination'] << { uid: site, name: opts['site_url'] }
    end
    body JSON.generate(config)
  else
    error('invalid_request')
  end
end

# Query
get '/micropub/:site' do |site|
  halt 404 unless settings.sites.include? site
  halt 404 unless params.include? 'q'

  @site ||= site

  case params['q']
    # TODO: Implement support for some of the extensions at https://indieweb.org/Micropub-extensions
  when /config/
    status 200
    headers 'Content-type' => 'application/json'
    # We are our own media-endpoint
    body JSON.generate({ "media-endpoint": "#{request.base_url}#{request.path}/media" })
  when /source/
    status 200
    headers 'Content-type' => 'application/json'
    # TODO: Determine what goes in here
    body JSON.generate(get_post(params[:url]))
  when /syndicate-to/
    status 200
    headers 'Content-type' => 'application/json'
    body syndicate_to
  end
end

# Multisite publishing - assumes mp-destination=site_section_name as per the config.yml
post '/micropub' do
  halt 404 unless params.include? 'mp-destination'
  site = params.delete('mp-destination')
  call! env.merge('PATH_INFO' => "/micropub/#{site}")
end

post '/micropub/:site' do |site|
  halt 404 unless settings.sites.include? site
  # If we're getting a file upload direct to this endpoint, jump to the media endpoint
  return call! env.merge('PATH_INFO' => "/micropub/#{site}/media") if params[:file]

  @site ||= site

  # Normalise params
  post_params = if env['CONTENT_TYPE'] == 'application/json'
                  JSON.parse(request.body.read.to_s, symbolize_names: true)
                else
                  params
                end
  post_params = process_params(post_params)

  # Check for reserved params which tell us what to do:
  # h = create entry
  # action = update, delete, undelete etc.
  error('invalid_request') unless post_params.any? { |k, _v| %i[h action].include? k }

  if post_params.key?(:h)
    error('insufficient_scope') unless @scopes.include?('create')
    logger.info post_params unless ENV['RACK_ENV'] == 'test'
    # Publish the post
    return publish_post post_params

    # Syndicate the post
    # syndicate_to post_params
  end

  if post_params.key?(:action)
    @action = post_params[:action]

    error('invalid_request') unless %w[update delete undelete].include? @action
    if @action == 'update'
      error('invalid_request') unless post_params.any? do |k, v|
        %i[add replace delete].include?(k) && v.respond_to?(:each)
      end
    end

    case @action
    when 'delete'
      error('insufficient_scope') unless @scopes.include?('delete')
      delete_post post_params
    when 'undelete'
      error('insufficient_scope') unless @scopes.include?('undelete')
      undelete_post post_params
    when 'update'
      error('insufficient_scope') unless @scopes.include?('update')
      update_post post_params
    end
    status 204
  end
end

post '/micropub/:site/media' do |site|
  halt 404 unless settings.sites.include? site
  error('insufficient_scope') unless @scopes.include?('create') || @scopes.include?('media')
  @site ||= site
  logger.info params

  file = params[:file]
  ext = file[:filename].split('.').last
  # Always generate a unique unguessable filename as per the spec
  filename = "#{SecureRandom.hex(6)}.#{ext}"
  upload_path = "#{image_dir}/#{filename}"
  media_path = "#{site_url}/#{upload_path}"

  files = {}
  files[upload_path] = Base64.encode64(file[:tempfile].read)

  commit_to_github(files, 'media', filename)

  status 201
  headers 'Location' => media_path
  body nil
end
