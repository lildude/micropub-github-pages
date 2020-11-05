# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__

class Authorization < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    stub_token
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
    get '/micropub/testsite', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.not_found?
  end

  def test_404_if_not_defined_site
    post '/micropub/foobar', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.not_found?
    assert last_response.body.include? 'Site not found!'
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
    post '/micropub/testsite', nil, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'invalid_request'
  end

  def test_authorized_if_access_token_query_param_and_no_action
    post '/micropub/testsite', access_token: '1234567890'
    refute last_response.unauthorized?
    assert last_response.bad_request?
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'invalid_request'
  end

  def test_scopes_enforced
    stub_token('delete')
    post '/micropub/testsite', { h: 'entry' }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'

    stub_token('undelete')
    post '/micropub/testsite', { h: 'entry' }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'

    stub_token('media')
    post '/micropub/testsite', { h: 'entry' }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'

    stub_token('create')
    post '/micropub/testsite', { action: 'delete' }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'

    stub_token('create')
    post '/micropub/testsite', { action: 'undelete' }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890'
    assert last_response.body.include? 'insufficient_scope'
  end
end
