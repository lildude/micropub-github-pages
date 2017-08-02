# frozen_string_literal: true
require 'simplecov'
require 'coveralls'
SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
]
SimpleCov.start do
   add_filter 'vendor'
end

require File.expand_path '../test_helper.rb', __FILE__

class MainAppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def helpers
    Class.new { include AppHelpers }
  end

  def setup
    @helper = helpers.new
  end

  #### ----- AppHelpers unit tests ----- ####
  def test_verify_token_valid
    stub_token
    @helper.instance_variable_set(:@access_token, "1234567890")
    result = @helper.verify_token
    assert result.include? :me
    assert result.include? :issued_by
    assert result.include? :client_id
    assert_equal "https://testsite.example.com", result[:me]
  end

  def test_jekyll_post_to_json
    content = "---\nlayout: post\ntags:\n- tag1\n- tag2\npermalink: \"/2017/07/foo-bar\"\ndate: 2017-07-22 10:56:22 +0100\n---\nThis is the content"
    assert_equal '{"type":["h-entry"],"properties":{"published":["2017-07-22 10:56:22 +0100"],"content":["This is the content"],"slug":["/2017/07/foo-bar"],"category":["tag1","tag2"]}}', @helper.jekyll_post_to_json(content)
  end

  def test_create_slug
    assert_equal "this-is-a-slug", @helper.create_slug({slug: "this-is-a-slug"})
    assert_equal "this-is-a-name-slug", @helper.create_slug({name: "This is a name 😜 Slug"})
    assert_equal "35782", @helper.create_slug({published: "2017-07-02 02:56:22 -0700"})
  end

  def test_slugify
    assert_equal "this-is-text", @helper.slugify('this is text')
    assert_equal "this-is-1234-no-emoji-or-punc", @helper.slugify('this is 🍎 1234 no emoji ! or punc')
    assert_equal "this-ends-in-emoji", @helper.slugify('tHis ends In emoji 🤡')
  end

  def test_create_permalink
    params = {
      permalink_style: "/:categories/:year/:month/:i_month/:day/:i_day/:short_year/:hour/:minute/:second/:title",
      slug: "foo-bar",
      published: "2017-07-02 02:56:22 -0700",
    }
    assert_equal "/2017/07/7/02/2/17/02/56/22/foo-bar", @helper.create_permalink(params)
  end

  def test_syndicate_to_get
    output = JSON.parse(@helper.syndicate_to)
    assert output.include? 'syndicate-to'
    assert_equal 'Twitter', output['syndicate-to'][0]['name']
    assert_equal 'https://twitter.com/lildude', output['syndicate-to'][0]['uid']
    refute output['syndicate-to'][0].include? 'silo_pub_token'
  end

  def test_syndicate_note
    stub_silo_pub
    @helper.instance_variable_set(:@content, 'this is the content')
    @helper.instance_variable_set(:@location, 'http://example.com/2010/01/14/12345')
    params = {:'syndicate-to' => ['https://twitter.com/lildude'], :content => 'this is the content'}
    assert_equal '12344321', @helper.syndicate_to(params)
    assert_nil @helper.syndicate_to({})
    assert_nil @helper.syndicate_to({:'syndicate-to' => ''})
  end

  def test_post_type
    assert_equal :article, @helper.post_type({h: "entry", name: "foo", content: "foo"})
    assert_equal :reply, @helper.post_type({h: "entry", in_reply_to: "foo"})
    assert_equal :repost, @helper.post_type({h: "entry", repost_of: "foo"})
    assert_equal :bookmark, @helper.post_type({h: "entry", bookmark_of: "foo"})
    assert_equal :note, @helper.post_type({h: "entry", content: "foo"})
    assert_equal :dump_all, @helper.post_type({h: "entry", ano: "foo"})
    assert_equal :event, @helper.post_type({h: "event", content: "foo"})
    assert_equal :cite, @helper.post_type({h: "cite", content: "foo"})
  end

  #### ---- Integration tests ---- ####
  def test_unauthorized_if_get_micropub_endpoint_without_token_or_header
    get '/micropub'
    assert last_response.unauthorized?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'unauthorized'
  end

  def test_404_if_get_known_site
    get '/micropub/testsite'
    assert last_response.unauthorized?
    assert last_response.body.include? 'unauthorized'
  end

  def test_404_if_get_known_site_without_query
    stub_token
    get '/micropub/testsite', nil, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'}
    assert last_response.not_found?
  end

  # TODO: update me when implementing a media-endpoint and syndicate-to
  def test_get_config_with_authorisation_header
    stub_token
    get '/micropub/testsite?q=config', nil, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'}
    assert last_response.ok?
    assert JSON.parse(last_response.body).empty?
  end

  # TODO: update me when implementing syndicate-to
  def test_get_syndicate_to
    stub_token
    get '/micropub/testsite?q=syndicate-to', nil, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'}
    assert last_response.ok?
    refute JSON.parse(last_response.body)["syndicate-to"].empty?
  end

  def test_get_source
    stub_token
    stub_github_search
    stub_existing_github_file
    get '/micropub/testsite?q=source&url=https://example.com/2010/01/14/example-post', nil, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'}
    assert last_response.ok?, "Expected 200 but got #{last_response.status}"
    assert JSON.parse(last_response.body)
    assert last_response.body.include? '"type":["h-entry"]'
    assert last_response.body.include? '"published":["2017-01-20 10:01:48 +0000"]'
    assert last_response.body.include? '"category":["foo","bar"]'
    assert last_response.body.include? '"slug":["/2017/01/this-is-a-test-post"]'
    assert last_response.body.include? '["This is a test post with:\\r\n\\r\n- Tags,\\r\n- a permalink\\r\n- and some **bold** and __italic__ markdown"]'
  end

  def test_get_specific_props_from_source
    skip('TODO: not yet implemented')
    stub_token
    stub_github_search
    stub_existing_github_file
    get '/micropub/testsite?q=source&properties[]=content&properties[]=category&url=https://example.com/2010/01/14/example-post', nil, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'}
    assert last_response.ok?, "Expected 200 but got #{last_response.status}"
    assert_equal '{"type":["h-entry"],"properties":{"published":["2017-01-28 16:52:30 +0000"],"content":["![](https://lildude.github.io//media/sunset.jpg)\n\nMicropub test of creating a photo referenced by URL"],"category":["foo","bar"]}}', last_response.body
  end

  def test_404_if_not_defined_site
    stub_token
    post '/micropub/foobar', nil, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'}
    assert last_response.not_found?
    assert last_response.body.include? '404: Not Found'
  end

  def test_unauthorized_if_no_auth_header_or_access_token_and_error_body_is_json
    post '/micropub/testsite'
    assert last_response.unauthorized?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'unauthorized'
  end

  def test_unauthorized_access_token_is_rejected
    stub_unauthed_token
    post '/micropub/testsite'
    assert last_response.unauthorized?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'unauthorized'
  end

  def test_authorized_if_access_token_response_has_no_scope
    stub_noscope_token_response
    post '/micropub/testsite', nil, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'}
    assert last_response.unauthorized?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'insufficient_scope'
  end

  def test_authorized_if_auth_header_and_no_action
    stub_token
    post '/micropub/testsite', nil, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'}
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'invalid_request'
  end

  def test_authorized_if_access_token_query_param_and_no_action
    stub_token
    post '/micropub/testsite', :access_token => '1234567890'
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'invalid_request'
  end

  def test_new_note_with_syndication_everything_and_unrecognised_params
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
      :h => "entry",
      :content => 'This is the content',
      :category => ['tag1', 'tag2'],
      :published => now.to_s,
      :slug => 'this-is-the-content-slug',
      'syndicate-to' => 'https://myfavoritesocialnetwork.example/lildude',
      :unrecog_param => 'foo',
      :ano_unrecog_param => 'bar'
      }, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? 'tag1'
    assert last_response.body.include? 'tag2'
    assert last_response.body.include? 'this-is-the-content-slug'
    assert last_response.body.include? now.to_s
    assert last_response.body.include? 'This is the content'
    assert_equal "https://example.com/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-the-content-slug", last_response.header['Location']
  end

  def test_new_entry
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
      :h => 'entry',
      :name => 'This is a 😍 Post!!',
      :content => 'This is the content',
      :category => ['tag1', 'tag2'],
      'syndicate-to' => 'https://myfavoritesocialnetwork.example/lildude'
      }, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_equal "https://example.com/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-a-post", last_response.header['Location']
  end

  def test_new_note_with_title_in_markdown_content_becomes_article
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
      :h => 'entry',
      :content => "# This is a 😍 Post!!\n\nThis is the content",
      :category => ['tag1', 'tag2']
    }, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got \n#{last_response.header}"
    assert_equal "https://example.com/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-a-post", last_response.header['Location'], "Expected Location header of: https://example.com/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-a-post but got \n#{last_response.header}"
    assert last_response.body.include?('tag1'), "Expected body to include tag 'tag1' but got \n#{last_response.body}"
    assert last_response.body.include?('tag2'), "Expected body to include tag 'tag2' but got \n#{last_response.body}"
    assert last_response.body.include?('This is a 😍 Post!!'), "Expected body to include 'This is a 😍 Post!!' but got \n#{last_response.body}"
    assert last_response.body.include?('This is the content'), "Expected body to include 'This is the content' but got \n#{last_response.body}"
  end

  def test_new_note_with_photo_reference
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_non_existant_github_file
    stub_put_github_request
    post('/micropub/testsite', {
      :h => 'entry',
      :content => 'Adding a new photo',
      :photo => 'https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg'
    }, {'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? '/img/12716713_162835967431386_291746593_n.jpg'
  end

  #----:[ HTTP Multipart ]:----#

  def test_new_entry_with_photo_multipart
    skip('TODO: not yet implemented')

  end

  def test_new_entry_with_two_photos_multipart
    skip('TODO: not yet implemented')
  end

  #----:[ JSON tests ]:----#

  def test_new_note_json_syntax
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
        :type => ['h-entry'],
        :properties => {
          :content => ['This is the JSON content'],
          :category => ['tag1', 'tag2']
          }
    }.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "https://example.com/#{now.strftime("%Y")}/#{now.strftime("%m")}/#{now.strftime("%s").to_i % (24 * 60 * 60)}", last_response.header['Location']
    assert last_response.body.include? 'tag1'
    assert last_response.body.include? 'tag2'
    assert last_response.body.include? 'This is the JSON content'
  end

  def test_new_note_with_html_json
    stub_token
    stub_get_github_request
    stub_put_github_request
    post('/micropub/testsite', {
        :type => ['h-entry'],
        :properties => {
          :content => [{
            'html': '<p>This post has <b>bold</b> and <i>italic</i> text.</p>'
            }],
          }
    }.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.body.include? '<p>This post has <b>bold</b> and <i>italic</i> text.</p>'
  end

  def test_new_note_with_title_in_markdown_content_becomes_article_json
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
        :type => ['h-entry'],
        :properties => {
          :content => ["# This is the header\n\nThis is the JSON content"],
          :category => ['tag1', 'tag2']
          }
    }.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "https://example.com/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-the-header", last_response.header['Location']
    assert last_response.body.include? 'tag1'
    assert last_response.body.include? 'tag2'
    assert last_response.body.include?('title: This is the header'), "Expected title to include 'This is the header', but got\n#{last_response.body}"
    refute last_response.body.include? '# This is the header'
    assert last_response.body.include? 'This is the JSON content'
  end

  def test_new_note_with_title_in_markdown_and_name_becomes_article_with_name_as_title
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
        :type => ['h-entry'],
        :properties => {
          :name => ["This is the title"],
          :content => ["# This is the header\n\nThis is the JSON content"],
          :category => ['tag1', 'tag2']
          }
    }.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "https://example.com/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-the-title", last_response.header['Location']
    assert last_response.body.include? 'tag1'
    assert last_response.body.include? 'tag2'
    assert last_response.body.include?('title: This is the title'), "Expected title to include 'This is the title', but got\n#{last_response.body}"
    assert last_response.body.include? '# This is the header'
    assert last_response.body.include? 'This is the JSON content'
  end

  def test_new_note_with_photo_reference_json
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_non_existant_github_file
    stub_put_github_request
    post('/micropub/testsite', {
        :type => ['h-entry'],
        :properties => {
          :content => ['Adding a new photo'],
          :photo => ['https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg']
          }
    }.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? '/img/12716713_162835967431386_291746593_n.jpg'
  end

  def test_new_note_with_unreachable_photo_reference_json
    stub_token
    stub_cant_get_photo
    stub_get_github_request
    stub_non_existant_github_file
    stub_put_github_request
    post('/micropub/testsite', {
        :type => ['h-entry'],
        :properties => {
          :content => ['Adding a new photo'],
          :photo => ['https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_nope.jpg']
          }
    }.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? 'https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_nope.jpg'
  end

  def test_new_note_with_multiple_photos_reference_json
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_non_existant_github_file
    stub_put_github_request
    post('/micropub/testsite', {
        :type => ['h-entry'],
        :properties => {
          :content => ['Adding a new photo'],
          :photo => ['https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg',
          'https://instagram.flhr2-1.fna.fbcdn.net/t51.2885-15/e35/13557237_1722207908037147_1805177879_n.jpg']
          }
    }.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? '/img/12716713_162835967431386_291746593_n.jpg'
  end

  def test_new_note_with_photo_reference_with_alt_json
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_non_existant_github_file
    stub_put_github_request
    post('/micropub/testsite', {
        :type => ['h-entry'],
        :properties => {
          :content => ['Adding a new photo'],
          :photo => [{
            :value => 'https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg',
            :alt => 'Instagram photo'
            }]
          }
    }.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? '/img/12716713_162835967431386_291746593_n.jpg'
    assert last_response.body.include? 'Instagram photo'
  end

  def test_h_entry_with_nested_object
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
        :type => ['h-entry'],
        :properties => {
          :summary => ['Weighed 70.64 kg'],
          :"x-weight" => [{
            :type => ['h-measure'],
            :properties => {
              :num => ['70.64'],
              :unit => ['kg']
            }
          }]
        }
    }.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "https://example.com/#{now.strftime("%Y")}/#{now.strftime("%m")}/#{now.strftime("%s").to_i % (24 * 60 * 60)}", last_response.header['Location']
    assert last_response.body.include?('Weighed 70.64 kg'), "Body did not include 'Weighed 70.64 kg'\n#{last_response.body}"
    assert last_response.body.include?('70.64'), 'Body did not include "70.64"'
    assert last_response.body.include?('kg'), 'Body did not include "kg"'
  end
end
