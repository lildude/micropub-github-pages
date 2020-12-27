# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__

class Query < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    stub_token
    env 'HTTP_AUTHORIZATION', 'Bearer 1234567890'
  end

  def test_get_config_for_all_sites
    get '/micropub?q=config'
    assert last_response.ok?
    parse_body = JSON.parse(last_response.body)
    assert_equal parse_body['destination'].count, 1
    assert_equal parse_body['destination'][0]['uid'], 'testsite'
    assert_equal parse_body['destination'][0]['name'], 'https://example.com'
    assert_equal parse_body['post-types'].count, 3

    get '/micropub?q=source'
    refute last_response.ok?
    assert last_response.body.include? 'invalid_request'
  end

  def test_get_config_with_authorisation_header
    get '/micropub/testsite?q=config'
    assert last_response.ok?
    parse_body = JSON.parse(last_response.body)
    refute parse_body.empty?
    assert_equal parse_body['media-endpoint'], 'http://example.org/micropub/testsite/media'
  end

  def test_get_syndicate_to
    get '/micropub/testsite?q=syndicate-to'
    assert last_response.ok?
    parse_body = JSON.parse(last_response.body)
    refute parse_body['syndicate-to'].empty?
    %w[flickr github mastodon meetup twitter].each_with_index do |dest, i|
      assert_equal parse_body['syndicate-to'][i]['uid'], dest
    end
  end

  def test_get_source
    stub_github_search
    stub_get_github_request
    stub_get_pages_branch
    get '/micropub/testsite?q=source&url=https://example.com/2010/01/14/example-post'
    assert last_response.ok?, "Expected 200 but got #{last_response.status}"
    assert JSON.parse(last_response.body)
    assert last_response.body.include? '"type":["h-entry"]'
    assert last_response.body.include? '"published":["2010-01-14 10:01:48 +0000"]'
    assert last_response.body.include? '"category":["foo","bar"]'
    assert last_response.body.include? '"slug":["/2010/01/this-is-a-test-post"]'
    assert last_response.body.include? '["This is a test post with:\n\n- Tags,\n- a permalink\n- and some **bold** and __italic__ markdown"]'
  end

  def test_400_get_source_not_found
    stub_github_search(count: 0)
    get '/micropub/testsite?q=source&url=https://example.com/2010/01/14/example-post'
    assert JSON.parse(last_response.body)
    assert last_response.body.include? 'invalid_request'
  end

  def test_get_specific_props_from_source
    stub_github_search
    stub_get_github_request
    get '/micropub/testsite?q=source&properties[]=content&properties[]=category&url=https://example.com/2010/01/14/example-post'
    assert last_response.ok?, "Expected 200 but got #{last_response.status}"
    parse_body = JSON.parse(last_response.body)
    assert_equal 2, parse_body['properties'].length
    refute parse_body['type']
    assert parse_body['properties']['content']
    assert parse_body['properties']['category']
  end
end
