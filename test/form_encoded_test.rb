# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__
require 'mocha/setup'

class FormEncodedTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_unauthorized_if_get_micropub_endpoint_without_token_or_header
    get '/micropub'
    assert last_response.unauthorized?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'unauthorized'
  end

  def test_401_if_get_known_site_without_token
    get '/micropub/testsite'
    assert last_response.unauthorized?
    assert last_response.body.include? 'unauthorized'
  end

  def test_404_if_get_known_site_without_query
    stub_token
    get '/micropub/testsite', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.not_found?
  end

  # TODO: update me when implementing a media-endpoint and syndicate-to
  def test_get_config_with_authorisation_header
    stub_token
    get '/micropub/testsite?q=config', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.ok?
    #assert JSON.parse(last_response.body).empty?
  end

  # TODO: update me when implementing syndicate-to
  def test_get_syndicate_to
    skip
    stub_token
    get '/micropub/testsite?q=syndicate-to', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.ok?
    refute JSON.parse(last_response.body)['syndicate-to'].empty?
  end

  def test_get_source
    stub_token
    stub_github_search
    stub_get_github_request
    stub_get_pages_branch
    get '/micropub/testsite?q=source&url=https://example.com/2010/01/14/example-post', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.ok?, "Expected 200 but got #{last_response.status}"
    assert JSON.parse(last_response.body)
    assert last_response.body.include? '"type":["h-entry"]'
    assert last_response.body.include? '"published":["2017-01-20 10:01:48 +0000"]'
    assert last_response.body.include? '"category":["foo","bar"]'
    assert last_response.body.include? '"slug":["/2017/01/this-is-a-test-post"]'
    assert last_response.body.include? '["This is a test post with:\\r\n\\r\n- Tags,\\r\n- a permalink\\r\n- and some **bold** and __italic__ markdown"]'
  end

  def test_400_get_source_not_found
    stub_token
    stub_github_search(count: 0)
    get '/micropub/testsite?q=source&url=https://example.com/2010/01/14/example-post', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'invalid_request'
  end

  def test_get_specific_props_from_source
    skip('TODO: not yet implemented')
    stub_token
    stub_github_search
    stub_get_github_request
    get '/micropub/testsite?q=source&properties[]=content&properties[]=category&url=https://example.com/2010/01/14/example-post', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.ok?, "Expected 200 but got #{last_response.status}"
    assert_equal '{"type":["h-entry"],"properties":{"published":["2017-01-28 16:52:30 +0000"],"content":["![](https://lildude.github.io//media/sunset.jpg)\n\nMicropub test of creating a photo referenced by URL"],"category":["foo","bar"]}}', last_response.body
  end

  def test_404_if_not_defined_site
    stub_token
    post '/micropub/foobar', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
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

  def test_forbidden_if_access_token_response_has_no_scope
    stub_noscope_token_response
    post '/micropub/testsite', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.forbidden?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'forbidden'
  end

  def test_authorized_if_auth_header_and_no_action
    stub_token
    post '/micropub/testsite', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'invalid_request'
  end

  def test_authorized_if_access_token_query_param_and_no_action
    stub_token
    post '/micropub/testsite', access_token: '1234567890'
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'invalid_request'
  end

  def test_scopes_enforced
    stub_token('delete')
    post '/micropub/testsite', {h: 'entry'}, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'

    stub_token('undelete')
    post '/micropub/testsite', {h: 'entry'}, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'

    stub_token('media')
    post '/micropub/testsite', {h: 'entry'}, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'

    stub_token('create')
    post '/micropub/testsite', {action: 'delete'}, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'

    stub_token('create')
    post '/micropub/testsite', {action: 'undelete'}, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'
  end

  def test_422_if_repo_not_found
    stub_token
    stub_get_github_request(code: 422)
    now = Time.now
    post('/micropub/testsite', {
           :h => 'entry',
           :content => 'This is the content',
           :category => %w[tag1 tag2],
           :published => [now.to_s],
           :slug => 'this-is-the-content-slug',
           'syndicate-to' => 'https://myfavoritesocialnetwork.example/lildude',
           :unrecog_param => 'foo',
           :ano_unrecog_param => 'bar'
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.body.include? 'invalid_repo'
    refute last_response.created?
  end

  def test_new_note_with_syndication_everything_and_unrecognised_params
    stub_token
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub/testsite', {
           :h => 'entry',
           :content => 'This is the content',
           :category => %w[tag1 tag2],
           :published => [now.to_s],
           :slug => 'this-is-the-content-slug',
           'syndicate-to' => 'https://myfavoritesocialnetwork.example/lildude',
           :unrecog_param => 'foo',
           :ano_unrecog_param => 'bar'
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? 'tag1'
    assert last_response.body.include? 'tag2'
    assert last_response.body.include? 'this-is-the-content-slug'
    assert last_response.body.include? now.to_s
    assert last_response.body.include? 'This is the content'
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-the-content-slug", last_response.header['Location']
  end

  def test_new_entry
    stub_token
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub/testsite', {
           :h => 'entry',
           :name => 'This is a 😍 Post!!',
           :content => 'This is the content',
           :category => %w[tag1 tag2],
           'syndicate-to' => 'https://myfavoritesocialnetwork.example/lildude'
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-a-post", last_response.header['Location']
  end

  def test_new_note_with_title_in_markdown_content_becomes_article
    stub_token
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub/testsite', {
           h: 'entry',
           content: "# This is a 😍 Post!!\n\nThis is the content",
           category: %w[tag1 tag2]
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got \n#{last_response.header}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-a-post", last_response.header['Location'], "Expected Location header of: https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-a-post but got \n#{last_response.header}"
    assert last_response.body.include?('tag1'), "Expected body to include tag 'tag1' but got \n#{last_response.body}"
    assert last_response.body.include?('tag2'), "Expected body to include tag 'tag2' but got \n#{last_response.body}"
    assert last_response.body.include?('This is a 😍 Post!!'), "Expected body to include 'This is a 😍 Post!!' but got \n#{last_response.body}"
    assert last_response.body.include?('This is the content'), "Expected body to include 'This is the content' but got \n#{last_response.body}"
  end

  def test_new_note_with_photo_reference
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
           h: 'entry',
           content: 'Adding a new photo',
           photo: 'https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg'
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? '/img/12716713_162835967431386_291746593_n.jpg'
  end

  def test_delete_post
    stub_token
    stub_github_search
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    # Explicitly mock so we can confirm we're getting the modified content as expected
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with(has_entry(fm_published: 'false'))
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
           action: 'delete',
           url: 'https://example.com/2017/01/this-is-a-test-post/'
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
  end

  def test_undelete_post
    stub_token
    stub_github_search
    # Stub a specific response with fm_published: false
    Sinatra::Application.any_instance.expects(:get_post)
                        .returns(
                          { type: ['h-entry'],
                            properties: {
                              published: ['2017-01-20 10:01:48 +0000'],
                              content: ['Micropub update test.'],
                              fm_published: 'false'
                            } }
                        )
    stub_get_pages_branch
    stub_post_github_request
    # Explicitly stub so we can confirm we're not getting the fm_published key
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with(Not(has_key(:fm_published)))
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
           action: 'undelete',
           url: 'https://example.com/2017/01/this-is-a-test-post/'
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
  end
end
