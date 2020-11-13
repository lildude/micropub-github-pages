# frozen_string_literal: true

# Put helper functions in a module for easy testing.
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
      description ||= "Repository doesn't exist."
    when 'unauthorized'
      code = 401
    end
    halt code, JSON.generate(error: error, error_description: description)
  end

  def verify_token
    return %w[create update delete undelete media] if ENV['RACK_ENV'] == 'development'

    resp = HTTParty.get(Sinatra::Application.settings.micropub[:token_endpoint], {
                          headers: {
                            'Accept' => 'application/x-www-form-urlencoded',
                            'Authorization' => "Bearer #{@access_token}"
                          }
                        })
    decoded_resp = Hash[URI.decode_www_form(resp.body)].transform_keys(&:to_sym)
    error('forbidden') unless (decoded_resp.include? :scope) && (decoded_resp.include? :me)

    decoded_resp[:scope].gsub(/post/, 'create').split(' ')
  end

  def publish_post(params)
    @location = params[:url] if params[:url]
    filename =  if @location
                  file_path(@location).split('/').last
                else
                  date = DateTime.parse(params[:published])
                  fn = date.strftime('%F')
                  file_slug = create_slug(params)
                  params[:slug] = file_slug if params[:'mp-slug']
                  fn << "-#{file_slug}.md"
                end

    loc = settings.sites[@site]['site_url'].dup
    @location ||= loc << create_permalink(params)

    files = {}

    # Download any photos we want to include in the commit
    if download_photos? && params[:photo]
      params[:photo] = download_photos(params[:photo])
      params[:photo].each do |photo|
        files.merge!(photo.delete('content')) if photo['content']
      end
    end

    post_type = params[:type]
    template = File.read("templates/#{post_type}.liquid")
    content = Liquid::Template.parse(template).render(stringify_keys(params))

    files["#{posts_dir}/#{filename}"] = Base64.encode64(content)

    commit_to_github(files, post_type)

    content if ENV['RACK_ENV'] == 'test'
  end

  # Files should be an array of path and base64 encoded content
  def commit_to_github(files, type)
    # Verify the repo exists
    client.repository?(github_repo)
    ref = "heads/#{client.pages(github_repo).source.branch}"
    sha_latest_commit = client.ref(github_repo, ref).object.sha
    sha_base_tree = client.commit(github_repo, sha_latest_commit).commit.tree.sha

    new_tree = files.map do |path, new_content|
      Hash(
        path: path,
        mode: '100644',
        type: 'blob',
        sha: client.create_blob(github_repo, new_content, 'base64')
      )
    end

    sha_new_tree = client.create_tree(github_repo, new_tree, base_tree: sha_base_tree).sha
    @action ||= 'new'
    commit_message = "#{@action.capitalize} #{type}: #{files.keys.first}"
    sha_new_commit = client.create_commit(
      github_repo,
      commit_message,
      sha_new_tree,
      sha_latest_commit
    ).sha
    client.update_ref(github_repo, ref, sha_new_commit)
  rescue Octokit::TooManyRequests, Octokit::AbuseDetected
    logger.info 'Being rate limited. Waiting...'
    sleep client.rate_limit.resets_in
    retry
    # TODO: this is too generic and hides other problems
  rescue Octokit::UnprocessableEntity
    error('invalid_repo')
  end

  # Download the photo and add to GitHub repo if config allows
  #
  # WARNING: the handling of alt in JSON may change in the future.
  # See https://www.w3.org/TR/micropub/#uploading-a-photo-with-alt-text
  #
  def download_photos(params)
    photos = []
    params.flatten.each_with_index do |photo, index|
      if photo.is_a?(String)
        alt = ''
        url = photo
      else
        alt = photo[:alt]
        url = photo[:value]
      end

      # Next if the URL matches our own site - we've already got the picture
      next photos[index] = { 'url' => url, 'alt' => alt } if url =~ /#{site_url}/

      # If we have a tempfile property, this is a multipart upload
      filename = if photo.is_a?(Hash)
                   tmpfile = photo[:tempfile] if photo.key?(:tempfile)
                   photo.key?(:filename) ? photo[:filename] : url
                 else
                   url
                 end
      # Always generate a unique unguessable filename as per the spec
      filename = "#{SecureRandom.hex(6)}.#{filename.split('.').last}"
      upload_path = "#{image_dir}/#{filename}"
      photo_path = ''.dup
      photo_path << site_url if full_image_urls?
      photo_path << "/#{upload_path}"
      unless tmpfile
        tmpfile = Tempfile.new(filename)
        File.open(tmpfile, 'wb') do |file|
          resp = HTTParty.get(url, stream_body: true, follow_redirects: true)
          raise unless resp.success?

          file.write resp.body
        end
      end
      content = { upload_path => Base64.encode64(tmpfile.read) }
      photos[index] = { 'url' => photo_path, 'alt' => alt, 'content' => content }
      # TODO: This is too greedy and hides legit problems
    rescue StandardError
      # Fall back to orig url if we can't download
      photos[index] = { 'url' => url, 'alt' => alt }
    end
    photos
  end

  # Grab the contents of the file referenced by the URL received from the client
  # This assumes the final part of the URL contains part of the filename as it
  # appears in the repository.
  def get_post(url, properties = [])
    path = file_path(url)
    content = client.contents(github_repo, path: path)
    decoded_content = Base64.decode64(content[:content]).force_encoding('UTF-8').encode if content
    data = jekyll_post(decoded_content)
    data[:url] = url
    return data if properties.empty?

    data.delete(:type)
    data[:properties].delete_if { |key, _| !properties.include? key.to_s }

    data
  end

  def file_path(url)
    fuzzy_filename = url.split('/').last
    code = client.search_code("filename:#{fuzzy_filename} repo:#{github_repo}")
    # This is an ugly hack because webmock doesn't play nice - https://github.com/bblimke/webmock/issues/449
    code = JSON.parse(code, symbolize_names: true) if ENV['RACK_ENV'] == 'test'
    # Error if we can't find a unique single post
    error('invalid_request', 'The post with the requested URL was not found') unless code[:total_count] == 1
    code[:items][0][:path]
  end

  def jekyll_post(content)
    # Taken from Jekyll's Jekyll::Document YAML_FRONT_MATTER_REGEXP
    matches = content.match(/\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)(.*)/m)
    front_matter = SafeYAML.load(matches[1])
    front_matter.delete('layout')
    content = matches[4]
    data = {}
    data[:type] = ['h-entry'] # TODO: Handle other types.
    properties = {}
    # Map Jekyll Frontmatter fields back to microformat h-entry field names
    properties[:name] = [front_matter.delete('title')] if front_matter['title']
    properties[:published] = [front_matter.delete('date').to_s]
    properties[:content] = content ? [content.strip] : ['']
    properties[:slug] = [front_matter.delete('permalink')] if front_matter['permalink']
    properties[:category] = front_matter.delete('tags') if front_matter['tags']
    # For everything else, map directly onto fm_* properties
    front_matter.each do |key, value|
      properties[:"fm_#{key}"] = [value]
    end

    data[:properties] = properties
    data
  end

  def create_slug(params)
    slug =
      # Use the provided slug
      if params[:"mp-slug"] && !params[:"mp-slug"].empty?
        params[:"mp-slug"].split('/').last
      # If there's a title, use that
      elsif params[:title] && !params[:title].empty?
        params[:title].gsub(/[^\w\s-]/, '')
      # If there's a name, use that
      elsif params[:name] && !params[:name].empty?
        params[:name].gsub(/[^\w\s-]/, '')
      elsif params[:content]
        # Else generate a slug based on the first 5 words of the first line of the content
        strip_hashtags(params[:content].gsub(/<[^>]*>/ui, '')).split(/\r?\n/).first.gsub(/[^\w\s-]/, '').split.first(5).join(' ')
      else
        # Else generate a slug based on the published date.
        DateTime.parse(params[:published]).strftime('%s').to_i % (24 * 60 * 60)
      end
    slug.to_s.to_url
  end

  def create_permalink(params)
    link_style = params[:permalink_style] || permalink_style
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
      ':title' => create_slug(params),
      ':categories' => ''
    }

    link_style.gsub(/(:[a-z_]+)/, template_variables).gsub(%r{(//)}, '/')
  end

  def stringify_keys(hash)
    hash.is_a?(Hash) ? hash.collect { |key, value| [key.to_s, stringify_keys(value)] }.to_h : hash
  end

  def strip_hashtags(text)
    text.gsub(/\B#(\w+)/, '').squeeze(' ').strip
  end

  def parse_hashtags(text)
    text.scan(/\B#(\w+)/).flatten
  end

  # Syndicate to destinations supported by Bridgy so we don't have implement all the APIs ourselves.
  # We make no attempt to verify if Bridgy has an account before attempting the webmention.
  # If no destination is provided, assume it's a query and return all destinations.
  # TODO: Implement settings to enable and provide specific options
  def syndicate_to(syndicate_to = nil, options = nil)
    destinations = %w[flickr github mastodon meetup twitter]

    dests = []
    destinations.each do |dest|
      dests << { uid: dest, name: dest == 'github' ? 'GitHub' : dest.capitalize }
    end
    return dests unless syndicate_to

    dest = syndicate_to.empty? ? nil : syndicate_to.first
    return nil unless dest && destinations.include?(dest)

    # TODO: Append formatting options
    # bridgy_omit_link=true|maybe|false
    # bridgy_ignore_formatting=true|false
    BridgyJob.perform_async(@location, dest, options)
  end

  # Process and clean up params for use later
  # TODO: Need to .to_yaml nested objects for easy access in the template
  def process_params(post_params)
    # Bump off the standard Sinatra params we don't use
    post_params.reject! { |key, _v| key =~ /^splat|captures|site/i }
    error('invalid_request') if post_params.empty?

    post_params = Hash[post_params].transform_keys(&:to_sym)
    post_params.merge!(post_params.delete(:properties)) if post_params[:properties]
    post_params[:h] = post_params[:type][0].tr('h-', '') if post_params[:type]

    content = post_params[:content].dup
    if content
      content = if content.is_a?(String)
                  content
                else
                  content = content.first
                  content.is_a?(Hash) && content.key?(:html) ? content[:html] : content
                end
    end

    %i[name slug published].each do |param|
      param_value = post_params[param]
      post_params[param] = param_value.first if param_value.is_a?(Array)
    end

    photo_param = post_params[:photo].dup
    if photo_param
      photos = []
      # micro.blog and Sunlit iOS apps use mp-photo-alt for photo alt
      mp_photo_alt = post_params.delete(:'mp-photo-alt')
      if mp_photo_alt
        photo_param.each_with_index do |photo, index|
          alt = mp_photo_alt[index]
          photos << { value: photo, alt: alt }
        end
      else
        photos = [photo_param]
      end
      post_params[:photo] = photos
    end

    post_params[:'syndicate-to'] = Array(*post_params[:'syndicate-to']) if post_params[:'syndicate-to']

    # Add additional properties, unless we're performing an action
    unless post_params.key? :action
      # Secret functionality: determine tags from content if none provided
      unless post_params[:category] || !content
        tags = parse_hashtags(content)
        post_params[:category] = tags unless tags.empty?
        content = strip_hashtags(content)
      end
      # Secret functionality: If the first line is a header, set the name with it
      first_line = content.match(/^#+\s?(.+$)\n+/) if content
      if first_line && !post_params[:name]
        post_params[:name] = first_line[1].to_s.strip
        content.sub!(first_line[0], '')
      end

      # Determine the template to use based on various params received.
      post_params[:type] = post_type(post_params)
      # Spec says we should use h-entry if no type provided.
      post_params[:h] = 'entry' unless post_params.include?(:h)
      # Honour the client's published date, if set, else set one.
      post_params[:published] = Time.now.to_s unless post_params[:published]
    end

    post_params[:content] = content if content
    post_params
  end

  def post_type(post_params)
    object_type = post_params[:h]
    case object_type
    when 'entry'
      mapping = { name: :article, in_reply_to: :reply, repost_of: :repost, bookmark_of: :bookmark, photo: :photo, content: :note }
      mapping.each { |key, type| return type if post_params.include?(key) && !post_params[key].empty? }
      # Dump all params into this template as it doesn't fit any other type.
      :dump_all
    else
      object_type.to_sym
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
      post_params[:add].each do |key, value|
        post[:properties].key?(key) ? post[:properties][key] += value : post[:properties][key] = value
      end
    elsif post_params.key? :delete
      post_params[:delete].each do |key, value|
        key.is_a?(String) ? post[:properties].delete(key.to_sym) : post[:properties][key] -= value
      end
    end

    updated_props = process_params(post)
    publish_post updated_props
  end

  private

  def client
    @client ||= Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
  end

  def site_global_default(opt, default: nil)
    if settings.sites[@site][opt]
      settings.sites[@site][opt]
    elsif settings.respond_to?(opt.to_sym)
      settings.send(opt.to_sym)
    else
      default
    end
  end

  def github_repo
    @github_repo ||= settings.sites[@site]['github_repo']
  end

  def permalink_style
    @permalink_style ||= settings.sites[@site]['permalink_style'] || settings.permalink_style
  end

  def site_url
    @site_url ||= settings.sites[@site]['site_url']
  end

  def full_image_urls?
    @full_image_urls ||= site_global_default('full_image_urls', default: true)
  end

  def image_dir
    @image_dir ||= site_global_default('image_dir', default: 'images')
  end

  def download_photos?
    @download_photos = site_global_default('download_photos', default: false)
  end

  def posts_dir
    @posts_dir ||= site_global_default('posts_dir', default: '_posts')
  end

  def syndicate_to_bridgy?
    @syndicate_to_bridgy ||= site_global_default('syndicate_to_bridgy', default: false)
  end

  def bridgy_options
    @bridgy_options ||= site_global_default('bridgy_options', default: { 'bridgy_omit_link' => false, 'bridgy_ignore_formatting' => false })
  end
end
