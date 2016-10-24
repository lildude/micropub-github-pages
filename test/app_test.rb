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

  def test_unauthorized_if_no_auth_header_or_access_token
    post '/micropub/testsite'
    assert last_response.unauthorized?
    assert last_response.body.include?('401: Unauthorized')
  end

  def test_authorized_if_auth_header_and_no_action
    stub_token
    post '/micropub/testsite', nil, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"}
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert last_response.body.include?('400: invalid_request')
  end

  def test_authorized_if_access_token_query_param_and_no_action
    stub_token
    post '/micropub/testsite', :access_token => "1234567890"
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert last_response.body.include?('400: invalid_request')
  end

  def test_new_note_with_syndication
    stub_token
    stub_get_github_request
    stub_put_github_request
    post('/micropub/testsite', {:h => "entry", :content => "This is the content", :category => ["tag1", "tag2"], "mp-syndicate-to" => "https://myfavoritesocialnetwork.example/lildude"}, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
  end

  def test_new_entry
    stub_token
    stub_get_github_request
    stub_put_github_request
    post('/micropub/testsite', {:h => "entry", :title => "This is a 😍 Post!!", :content => "This is the content", :category => ["tag1", "tag2"], "mp-syndicate-to" => "https://myfavoritesocialnetwork.example/lildude"}, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
  end
end
