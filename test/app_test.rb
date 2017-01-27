require 'simplecov'
require 'coveralls'
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
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

  def test_unauthorized_if_get_micropub_endpoint_without_token_or_header
    get '/micropub'
    assert last_response.unauthorized?
    assert JSON.parse(last_response.body)
    assert last_response.body.include?('unauthorized')
  end

  def test_404_if_get_known_site
    get '/micropub/testsite'
    assert last_response.unauthorized?
    assert last_response.body.include?('unauthorized')
  end

  def test_404_if_get_known_site_without_query
    stub_token
    get '/micropub/testsite', nil, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"}
    assert last_response.not_found?
  end

  def test_get_config_with_authorisation_header
    stub_token
    get '/micropub/testsite?q=config', nil, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"}
    assert last_response.ok?
    # TODO: Assert the correct JSON content
  end

  def test_get_syndicate_to
    skip("TODO")
    stub_token
    get '/micropub/testsite?q=syndicate-to', nil, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"}
    assert last_response.ok?
    assert_equal "foo", last_response.body
  end


  def test_404_if_not_defined_site
    stub_token
    post '/micropub/foobar', nil, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"}
    assert last_response.not_found?
    assert last_response.body.include?('404: Not Found')
  end

  def test_unauthorized_if_no_auth_header_or_access_token_and_error_body_is_json
    post '/micropub/testsite'
    assert last_response.unauthorized?
    assert JSON.parse(last_response.body)
    assert last_response.body.include?('unauthorized')
  end

  def test_authorized_if_access_token_response_has_no_scope
    stub_noscope_token_response
    post '/micropub/testsite', nil, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"}
    assert last_response.unauthorized?
    assert JSON.parse(last_response.body)
    assert last_response.body.include?('insufficient_scope')
  end

  def test_authorized_if_auth_header_and_no_action
    stub_token
    post '/micropub/testsite', nil, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"}
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert JSON.parse(last_response.body)
    assert last_response.body.include?('invalid_request')
  end

  def test_authorized_if_access_token_query_param_and_no_action
    stub_token
    post '/micropub/testsite', :access_token => "1234567890"
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert JSON.parse(last_response.body)
    assert last_response.body.include?('invalid_request')
  end

  def test_new_note_with_syndication_everything_and_unrecognised_params
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
      :h => "entry",
      :content => "This is the content",
      :category => ["tag1", "tag2"],
      :published => now.to_s,
      :slug => "this-is-the-content-slug",
      "mp-syndicate-to" => "https://myfavoritesocialnetwork.example/lildude",
      :unrecog_param => "foo",
      :ano_unrecog_param => "bar"
      }, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_equal "---\nlayout: note\ntags: tag1, tag2\npermalink: this-is-the-content-slug\ndate: #{now.to_s}\n---\nThis is the content", last_response.body
    assert_equal "/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-the-content-slug", last_response.header['Location']
  end

  def test_new_entry
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
      :h => "entry",
      :name => "This is a 😍 Post!!",
      :content => "This is the content",
      :category => ["tag1", "tag2"],
      "mp-syndicate-to" => "https://myfavoritesocialnetwork.example/lildude"
      }, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_equal "/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-a-post", last_response.header['Location']
  end

  def test_new_note_with_title_in_markdown_content_becomes_article
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
      :h => "entry",
      :content => "# This is a 😍 Post!!\n\nThis is the content",
      :category => ["tag1", "tag2"]
    }, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_equal "/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-a-post", last_response.header['Location']
    assert_equal "---\nlayout: post\ntitle: This is a 😍 Post!!\ntags: tag1, tag2\ndate: #{now}\n---\nThis is the content", last_response.body
  end

  def test_new_note_with_photo_reference
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_non_existant_github_file
    stub_put_github_request
    post('/micropub/testsite', {
      :h => "entry",
      :content => "Adding a new photo",
      :photo => "https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg"
    }, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_match /!\[\]\(\/img\/12716713_162835967431386_291746593_n\.jpg\)/, last_response.body
  end

  #----:[ JSON tests ]:----#

  def test_new_note_json_syntax
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
        :type => ["h-entry"],
        :properties => {
          :content => ["This is the JSON content"],
          :category => ["tag1", "tag2"]
          }
    }.to_json, {"CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "/#{now.strftime("%Y")}/#{now.strftime("%m")}/#{now.strftime("%s").to_i % (24 * 60 * 60)}", last_response.header['Location']
  end

  def test_new_note_with_title_in_markdown_content_becomes_article_json
    stub_token
    stub_get_github_request
    stub_put_github_request
    now = Time.now
    post('/micropub/testsite', {
        :type => ["h-entry"],
        :properties => {
          :content => ["# This is the header\n\nThis is the JSON content"],
          :category => ["tag1", "tag2"]
          }
    }.to_json, {"CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "/#{now.strftime("%Y")}/#{now.strftime("%m")}/this-is-the-header", last_response.header['Location']
    assert_equal "---\nlayout: post\ntitle: This is the header\ntags: tag1, tag2\ndate: #{now.to_s}\n---\nThis is the JSON content", last_response.body
  end

  def test_new_note_with_photo_reference_json
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_non_existant_github_file
    stub_put_github_request
    post('/micropub/testsite', {
        :type => ["h-entry"],
        :properties => {
          :content => ["Adding a new photo"],
          :photo => ["https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg"]
          }
    }.to_json, {"CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_match /!\[\]\(\/img\/12716713_162835967431386_291746593_n\.jpg\)/, last_response.body
  end

  def test_new_note_with_photo_reference_with_alt_json
    skip("TODO")
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_non_existant_github_file
    stub_put_github_request
    post('/micropub/testsite', {
        :type => ["h-entry"],
        :properties => {
          :content => ["Adding a new photo"],
          :photo => [{
            :value => "https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg",
            :alt => "Instagram photo"
            }]
          }
    }.to_json, {"CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_match /!\[Instagram photo\]\(\/media\/12716713_162835967431386_291746593_n\.jpg\)/, last_response.body
  end

end
