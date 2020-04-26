# frozen_string_literal: true

require 'sinatra'
require 'sinatra/config_file'
require 'sinatra/content_for'
require 'uri'
require 'octokit'
require 'httparty'
require 'json'
require 'base64'
require 'open-uri'
require 'safe_yaml'
require 'liquid'
require 'sinatra/reloader' if development?
require './env' if File.exist?('env.rb')

SafeYAML::OPTIONS[:default_mode] = :safe

configure { set :server, :puma }

config_yml = "#{::File.dirname(__FILE__)}/config.yml"
config_yml = "#{::File.dirname(__FILE__)}/test/fixtures/config.yml" if test?

config_file config_yml

# Default settings if not set in config
configure { set download_photos: false } unless settings.respond_to?(:download_photos)
configure { set syndicate_to: {} } unless settings.respond_to?(:syndicate_to)

# Put helper functions in a module for easy testing.
# https://www.w3.org/TR/micropub/#error-response
module AppHelpers
  def error(error, description = nil)
    case error
    when 'invalid_request'
      code = 400
      description ||= 'Invalid request'
    when 'insufficient_scope'
      code = 401
      description ||= 'Insufficient scope information provided.'
    when 'forbidden'
      code = 403
      description ||= 'Forbidden'
    when 'invalid_repo'
      code = 422
      description ||= "Repository doesn't exit."
    when 'unauthorized'
      code = 401
    end
    halt code, JSON.generate(error: error, error_description: description)
  end

  def verify_token
    resp = HTTParty.get(Sinatra::Application.settings.micropub[:token_endpoint], {
                          headers: {
                            'Content-type' => 'application/x-www-form-urlencoded',
                            'Authorization' => "Bearer #{@access_token}"
                          }
                        })
    decoded_resp = Hash[URI.decode_www_form(resp)].transform_keys(&:to_sym)
    error('insufficient_scope') unless (decoded_resp.include? :scope) && (decoded_resp.include? :me)

    decoded_resp
  end

  def publish_post(params)
    # Authenticate
    client = Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])

    date = DateTime.parse(params[:published])
    filename = date.strftime('%F')
    params[:slug] = create_slug(params)
    filename << "-#{params[:slug]}.md"

    logger.info "Filename: #{filename}"
    @location = settings.sites[@site]['site_url'].dup
    @location << create_permalink(params)

    # Verify the repo exists
    begin
      client.repository?(settings.sites[@site]['github_repo'])
    rescue Octokit::UnprocessableEntity
      error('invalid_repo')
    end

    files = {}

    # Download any photos we want to include in the commit
    # TODO: Per-repo settings take pref over global. Global only at the mo
    if settings.download_photos && (!params[:photo].nil? && !params[:photo].empty?)
      params[:photo] = download_photos(params)
      params[:photo].each do |photo|
        files.merge!(photo.delete('content')) if photo['content']
      end
    end

    template = File.read("templates/#{params[:type]}.liquid")
    content = Liquid::Template.parse(template).render(stringify_keys(params))

    ref = client.pages(settings.sites[@site]['github_repo']).source.branch
    sha_latest_commit = client.ref(settings.sites[@site]['github_repo'], ref).object.sha
    sha_base_tree = client.commit(settings.sites[@site]['github_repo'], sha_latest_commit).commit.tree.sha

    files["_posts/#{filename}"] = Base64.encode64(content)

    new_tree = files.map do |path, new_content|
      Hash(
        path: path,
        mode: '100644',
        type: 'blob',
        sha: client.create_blob(settings.sites[@site]['github_repo'], new_content, 'base64')
      )
    end

    sha_new_tree = client.create_tree(settings.sites[@site]['github_repo'], new_tree, base_tree: sha_base_tree).sha
    @action ||= 'new'
    commit_message = "#{@action.capitalize} #{params[:type]}"
    sha_new_commit = client.create_commit(
      settings.sites[@site]['github_repo'],
      commit_message,
      sha_new_tree,
      sha_latest_commit
    ).sha
    client.update_ref(settings.sites[@site]['github_repo'], ref, sha_new_commit)

    status 201
    headers 'Location' => @location.to_s
    body content if ENV['RACK_ENV'] == 'test'
  end

  # Download the photo and add to GitHub repo if config allows
  #
  # WARNING: the handling of alt in JSON may change in the future.
  # See https://www.w3.org/TR/micropub/#uploading-a-photo-with-alt-text
  def download_photos(params)
    params[:photo].flatten.each_with_index do |photo, i|
      alt = photo.is_a?(String) ? '' : photo[:alt]
      url = photo.is_a?(String) ? photo : photo[:value]
      # If we have a tempfile property, this is a multipart upload
      tmpfile = photo[:tempfile] if photo.is_a?(Hash) && photo.key?(:tempfile)
      filename = photo.is_a?(Hash) && photo.key?(:filename) ? photo[:filename] : url.split('/').last
      upload_path = "#{settings.sites[@site]['image_dir']}/#{filename}"
      photo_path = ''.dup
      photo_path << settings.sites[@site]['site_url'] if settings.sites[@site]['full_image_urls']
      photo_path << "/#{upload_path}"
      unless tmpfile
        tmpfile = Tempfile.new(filename)
        File.open(tmpfile, 'wb') do |f|
          resp = HTTParty.get(url, stream_body: true, follow_redirects: true)
          raise unless resp.success?

          f.write resp.body
        end
      end
      content = { upload_path => Base64.encode64(tmpfile.read) }
      params[:photo][i] = { 'url' => photo_path, 'alt' => alt, 'content' => content }
      # TODO: This is too greedy and hides legit problems
    rescue StandardError
      # Fall back to orig url if we can't download
      params[:photo][i] = { 'url' => url, 'alt' => alt }
    end
    params[:photo]
  end

  # Grab the contents of the file referenced by the URL received from the client
  # This assumes the final part of the URL contains part of the filename as it
  # appears in the repository.
  def get_post(url)
    fuzzy_filename = url.split('/').last
    client = Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
    code = client.search_code("filename:#{fuzzy_filename} repo:#{settings.sites[@site]['github_repo']}")
    # This is an ugly hack because webmock doesn't play nice - https://github.com/bblimke/webmock/issues/449
    code = JSON.parse(code, symbolize_names: true) if ENV['RACK_ENV'] == 'test'
    # Error if we can't find the post
    error('invalid_request', 'The post with the requested URL was not found') if (code[:total_count]).zero?

    content = client.contents(settings.sites[@site]['github_repo'], path: code[:items][0][:path]) if code[:total_count] == 1
    decoded_content = Base64.decode64(content[:content]).force_encoding('UTF-8').encode unless content.nil?

    jekyll_post(decoded_content)
  end

  def jekyll_post(content)
    # Taken from Jekyll's Jekyll::Document YAML_FRONT_MATTER_REGEXP
    matches = content.match(/\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)(.*)/m)
    front_matter = SafeYAML.load(matches[1])
    front_matter.delete('layout')
    content = matches[4]
    data = {}
    data[:type] = ['h-entry'] # TODO: Handle other types.
    data[:properties] = {}
    # Map Jekyll Frontmatter fields back to microformat h-entry field names
    data[:properties][:name] = [front_matter.delete('title')] if front_matter['title']
    data[:properties][:published] = [front_matter.delete('date').to_s]
    data[:properties][:content] = content.nil? ? [''] : [content.strip]
    # TODO: This should prob be url, but need to chec the behaviour of the various clients first
    data[:properties][:slug] = [front_matter.delete('permalink')] unless front_matter['permalink'].nil?
    data[:properties][:category] = front_matter.delete('tags') unless front_matter['tags'].nil? || front_matter['tags'].empty?
    # For everything else, map directly onto fm_* properties
    front_matter.each do |k, v|
      data[:properties][:"fm_#{k}"] = [v]
    end

    data
  end

  def create_slug(params)
    # Use the provided slug
    slug =
      if params.include?(:slug) && !params[:slug].nil?
        File.basename(params[:slug])
      # If there's a name, use that
      elsif params.include?(:name) && !params[:name].nil?
        slugify params[:name]
      else
        # Else generate a slug based on the published date.
        DateTime.parse(params[:published]).strftime('%s').to_i % (24 * 60 * 60)
      end
    slug.to_s
  end

  def create_permalink(params)
    permalink_style = params[:permalink_style] || settings.sites[@site]['permalink_style']
    date = DateTime.parse(params[:published])

    # Common Jekyll permalink template variables - https://jekyllrb.com/docs/permalinks/#template-variables
    template_variables = {
      ':year' => date.strftime('%Y'),
      ':month' => date.strftime('%m'),
      ':i_month' => date.strftime('%-m'),
      ':day' => date.strftime('%d'),
      ':i_day' => date.strftime('%-d'),
      ':short_year' => date.strftime('%y'),
      ':hour' => date.strftime('%H'),
      ':minute' => date.strftime('%M'),
      ':second' => date.strftime('%S'),
      ':title' => params[:slug],
      ':categories' => ''
    }

    permalink_style.gsub(/(:[a-z_]+)/, template_variables).gsub(%r{(//)}, '/')
  end

  def slugify(text)
    text.downcase.gsub('/[\s.\/_]/', ' ').gsub(/[^\w\s-]/, '').squeeze(' ').tr(' ', '-').chomp('-')
  end

  def stringify_keys(hash)
    hash.is_a?(Hash) ? hash.collect { |k, v| [k.to_s, stringify_keys(v)] }.to_h : hash
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
      clean_dests << e.reject { |k| k == 'silo_pub_token' }
    end
    return JSON.generate("syndicate-to": clean_dests) if params.nil?

    dest_entry = destinations.find do |d|
      dest = params[:"syndicate-to"][0] if params.key?(:"syndicate-to")
      d['uid'] == dest
    end || return

    silo_pub_token = dest_entry['silo_pub_token']
    uri = URI.parse('https://silo.pub/micropub')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.port == 443)
    request = Net::HTTP::Post.new(uri.request_uri)
    request.initialize_http_header('Authorization' => "Bearer #{silo_pub_token}")

    form_data = {}
    form_data['name'] = params[:name] if params[:name]
    form_data['url'] = @location
    form_data['content'] = params[:content]

    request.set_form_data(form_data)
    resp = http.request(request)
    JSON.parse(resp.body)['id_str'] if ENV['RACK_ENV'] == 'test'
  end

  # Process and clean up params for use later
  # TODO: Need to .to_yaml nested objects for easy access in the template
  def process_params(post_params)
    # Bump off the standard Sinatra params we don't use
    post_params.reject! { |key, _v| key =~ /^splat|captures|site/i }

    error('invalid_request') if post_params.empty?

    # JSON-specific processing
    if post_params.key?(:type) && !post_params.key?(:action)
      post_params[:h] = post_params[:type][0].tr('h-', '') if post_params[:type][0]
      post_params.merge!(post_params.delete(:properties))
      if post_params[:content]
        post_params[:content] =
          if post_params[:content][0].is_a?(Hash)
            post_params[:content][0][:html]
          else
            post_params[:content][0]
          end
      end
      post_params[:name] = post_params[:name][0] if post_params[:name]
      post_params[:slug] = post_params[:slug][0] if post_params[:slug]
    else
      # Convert all keys to symbols from form submission
      post_params = Hash[post_params].transform_keys(&:to_sym)
      post_params[:photo] = [post_params[:photo]] if post_params[:photo]
      post_params[:"syndicate-to"] = [*post_params[:"syndicate-to"]] if post_params[:"syndicate-to"]
    end

    # Secret functionality: We may receive markdown in the content.
    # If the first line is a header, set the name with it
    first_line = post_params[:content].match(/^#+\s?(.+$)\n+/) if post_params[:content]
    if !first_line.nil? && !post_params[:name]
      post_params[:name] = first_line[1].to_s.strip
      post_params[:content].sub!(first_line[0], '')
    end

    # Determine the template to use based on various params received.
    post_params[:type] = post_type(post_params) unless post_params.key? :action

    # Add in a few more params if they're not set
    unless post_params.include?(:action)
      # Spec says we should use h-entry if no type provided.
      post_params[:h] = 'entry' unless post_params.include?(:h)
      # It's nice to honour the client's published date, if set, else set one.
      post_params[:published] = if post_params.include? :published
                                  post_params[:published].first
                                else
                                  Time.now.to_s
                                end
    end
    post_params
  end

  def post_type(post_params)
    case post_params[:h]
    when 'entry'
      mapping = { name: :article, in_reply_to: :reply, repost_of: :repost, bookmark_of: :bookmark, content: :note }
      mapping.each { |key, type| return type if post_params.include?(key) }
      # Dump all params into this template as it doesn't fit any other type.
      :dump_all
    else
      post_params[:h].to_sym
    end
  end

  # Delete post doesn't delete the file. Instead it sets "publised: false".
  # This allows for undeletion later as we simply remove the property.
  def delete_post(post_params)
    post_params[:replace] = { fm_published: 'false' }
    update_post(post_params)
  end

  # Undelete assumes there is a "published" field in the front matter and removes it
  def undelete_post(post_params)
    post_params[:delete] = ['fm_published']
    update_post(post_params)
  end

  def update_post(post_params)
    post = get_post(post_params[:url])

    if post_params.key? :replace
      post[:properties].merge!(post_params[:replace])
    elsif post_params.key? :add
      post_params[:add].each do |k, v|
        post[:properties].key?(k) ? post[:properties][k] += v : post[:properties][k] = v
      end
    elsif post_params.key? :delete
      post_params[:delete].each do |k, v|
        k.is_a?(String) ? post[:properties].delete(k.to_sym) : post[:properties][k] -= v
      end
    end

    updated_props = process_params(post)
    publish_post updated_props
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
  elsif params['access_token']
    @access_token = params['access_token']
  else
    logger.info 'Received request without a token'
    error('unauthorized')
  end

  # Remove the access_token to prevent any accidental exposure later
  params.delete('access_token')

  # Verify the token
  verify_token unless ENV['RACK_ENV'] == 'development'
end

# Query
get '/micropub/:site' do |site|
  halt 404 unless settings.sites.include? site
  halt 404 unless params.include? 'q'

  @site ||= site

  case params['q']
  when /config/
    status 200
    headers 'Content-type' => 'application/json'
    # TODO: Populate this with media-endpoint and syndicate-to when supported.
    #       Until then, empty object is fine.
    body JSON.generate({})
  when /source/
    status 200
    headers 'Content-type' => 'application/json'
    # body JSON.generate("response": get_post(params[:url]))
    # TODO: Determine what goes in here
    body JSON.generate(get_post(params[:url]))
  when /syndicate-to/
    status 200
    headers 'Content-type' => 'application/json'
    body syndicate_to
  end
end

post '/micropub/:site' do |site|
  halt 404 unless settings.sites.include? site

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
      delete_post post_params
    when 'undelete'
      undelete_post post_params
    when 'update'
      update_post post_params
    end
  end
end
