# frozen_string_literal: true

require "base64"
require "digest"
require "httparty"
require "json"
require "liquid"
require "octokit"
require "safe_yaml"
require "securerandom"
require "sucker_punch" # This must go before sinatra
require "sinatra"
require "sinatra/config_file"
require "sinatra/json"
require "sinatra/reloader" if development?
require "stringex"
require_relative "lib/bridgy_job"
require_relative "lib/helpers"
require "./env" if File.exist?("env.rb")

SafeYAML::OPTIONS[:default_mode] = :safe

configure { set :server, :puma }

config_yml = test? ? "#{File.dirname(__FILE__)}/test/fixtures/config.yml" : "#{File.dirname(__FILE__)}/config.yml"

# Override config file if CONFIG env var is set
if ENV["SITES_CONFIG"] && !ENV["SITES_CONFIG"].empty?
  puts "Using configuration from SITES_CONFIG"
  config_yml = Tempfile.new(["config-", ".yml"])
  File.write(config_yml, JSON.parse(ENV["SITES_CONFIG"]).to_yaml)
end

config_file config_yml

Sinatra::Application.helpers AppHelpers

before do
  # Pull out and verify the authorization header or access_token
  if env["HTTP_AUTHORIZATION"]
    header = env["HTTP_AUTHORIZATION"].match(/Bearer (.*)$/)
    @access_token = header[1] unless header.nil?
  elsif params["access_token"]
    @access_token = params["access_token"]
  else
    logger.info "Received request without a token"
    error("unauthorized")
  end

  # Remove the access_token to prevent any accidental exposure later
  params.delete("access_token")

  # Verify the token and extract scopes
  @scopes = verify_token
end

# Multiple site query
get "/micropub" do
  halt 404, "Missing query" unless params.include? "q"
  if params["q"] == "config"
    status 200
    headers "Content-type" => "application/json"
    config = {"media-endpoint": "#{request.base_url}/dev/media"}
    config["destination"] = []
    settings.sites.each do |site, opts|
      config["destination"] << {uid: site, name: opts["site_url"]}
    end
    config["post-types"] = post_types
    config["syndicate-to"] = syndicate_to_bridgy? ? syndicate_to : []
    body JSON.generate(config)
  else
    error("invalid_request")
  end
end

# Query
get "/micropub/:site" do |site|
  halt 404, "Site not found!" unless settings.sites.include? site
  halt 404, "Missing query for site" unless params.include? "q"

  @site ||= site

  status 200
  headers "Content-type" => "application/json"
  case params["q"]
    # TODO: Implement support for some of the extensions at https://indieweb.org/Micropub-extensions
  when /config/
    # We are our own media-endpoint
    config = {"media-endpoint": "#{request.base_url}#{request.path}/media"}
    config["syndicate-to"] = syndicate_to_bridgy? ? syndicate_to : []
    body json(config)
  when /source/
    properties = params["properties"] || []
    body json(get_post(params[:url], properties))
  when /syndicate-to/
    dests = syndicate_to_bridgy? ? syndicate_to : []
    body json("syndicate-to": dests)
  end
end

# Multisite publishing - assumes mp-destination=site_section_name as per the config.yml
post "/micropub" do
  halt 404, "No destination" unless params.include? "mp-destination"
  site = params.delete("mp-destination")
  call! env.merge("PATH_INFO" => "/micropub/#{site}")
end

post "/micropub/:site" do |site|
  halt 404, "Site not found!" unless settings.sites.include? site
  # If we're getting a file upload direct to this endpoint, jump to the media endpoint
  return call! env.merge("PATH_INFO" => "/micropub/#{site}/media") if params[:file]

  @site ||= site

  # Normalise params
  post_params = if env["CONTENT_TYPE"] == "application/json"
    JSON.parse(request.body.read.to_s, symbolize_names: true)
  else
    params
  end
  post_params = process_params(post_params)

  # Check for reserved params which tell us what to do:
  # h = create entry
  # action = update, delete, undelete etc.
  error("invalid_request") unless post_params.any? { |k, _v| %i[h action].include? k }

  if post_params.key?(:h)
    error("insufficient_scope") unless @scopes.include?("create")
    # Publish the post
    content = publish_post post_params
    # Syndicate the post
    syndicate_to(post_params[:'mp-syndicate-to'], bridgy_options)

    # Return 202 as we don't publish immediately as we rely on GitHub Pages etc to do that
    status 202
    headers "Location" => @location.to_s
    body content if ENV["RACK_ENV"] == "test"

    return
  end

  if post_params.key?(:action)
    @action = post_params[:action]

    error("invalid_request") unless %w[update delete undelete].include? @action
    error("invalid_request") if @action == "update" && post_params.none? do |k, v|
      %i[add replace delete].include?(k) && v.respond_to?(:each)
    end

    case @action
    when "delete"
      error("insufficient_scope") unless @scopes.include?("delete")
      delete_post post_params
    when "undelete"
      error("insufficient_scope") unless @scopes.include?("undelete")
      undelete_post post_params
    when "update"
      error("insufficient_scope") unless @scopes.include?("update")
      update_post post_params
    end
    status 204
  end
end

post "/micropub/:site/media" do |site|
  halt 404, "Site not found!" unless settings.sites.include? site
  error("insufficient_scope") unless @scopes.include?("create") || @scopes.include?("media")
  @site ||= site

  file = params[:file]
  ext = file[:filename].split(".").last
  # Always generate a unique unguessable filename as per the spec
  filename = "#{SecureRandom.hex(6)}.#{ext}"
  upload_path = "#{image_dir}/#{filename}"
  media_path = "#{site_url}/#{upload_path}"

  files = {}
  files[upload_path] = Base64.encode64(file[:tempfile].read)

  commit_to_github(files, "media")

  status 201
  headers "Location" => media_path
  body nil
end
