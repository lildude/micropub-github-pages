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

  def test_authorized_if_auth_header
    stub_token
    post '/micropub/testsite', nil, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"}
    assert last_response.ok?
    refute last_response.unauthorized?
    assert last_response.body.include?('0987654321')
  end

  def test_authorized_if_access_token_query_param
    stub_token
    post '/micropub/testsite', :access_token => "1234567890"
    assert last_response.ok?
    refute last_response.unauthorized?
  end

  def test_new_note_with_syndication
    stub_token
    post('/micropub/testsite', {:h => "entry", :content => "This is the content", :category => ["tag1", "tag2"], "mp-syndicate-to" => "https://myfavoritesocialnetwork.example/lildude"}, {"HTTP_AUTHORIZATION" => "Bearer 1234567890"})
    assert last_response.ok?
  end
end
