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

  def test_404_if_get_micropub_endpoint
    get '/micropub'
    assert last_response.not_found?
    assert last_response.body.include?('404: Not Found')
  end

  def test_404_if_get_known_site
    get '/micropub/testsite'
    assert last_response.not_found?
    assert last_response.body.include?('404: Not Found')
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
    now = Time.now.to_s
    post('/micropub/testsite', {
      :h => "entry",
      :content => "This is the content",
      :category => ["tag1", "tag2"],
      :published => now,
      :slug => "this-is-the-content-slug",
      "mp-syndicate-to" => "https://myfavoritesocialnetwork.example/lildude",
      :unrecog_param => "foo",
      :ano_unrecog_param => "bar"
      }, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_equal "---\nlayout: note\ntags: tag1, tag2\npermalink: this-is-the-content-slug\ndate: #{now}\n---\n\This is the content", last_response.body
  end

  def test_new_entry
    stub_token
    stub_get_github_request
    stub_put_github_request
    post('/micropub/testsite', {
      :h => "entry",
      :name => "This is a 😍 Post!!",
      :content => "This is the content",
      :category => ["tag1", "tag2"],
      "mp-syndicate-to" => "https://myfavoritesocialnetwork.example/lildude"
      }, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
  end
end
