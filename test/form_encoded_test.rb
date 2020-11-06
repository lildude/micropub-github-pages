# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__

class FormEncoded < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    stub_token
    env 'HTTP_AUTHORIZATION', 'Bearer 1234567890'
  end

  def test_422_if_repo_not_found
    stub_get_github_request(code: 422)
    now = Time.now
    post('/micropub/testsite', {
           :h => 'entry',
           :content => 'This is the content',
           :category => %w[tag1 tag2],
           :published => [now.to_s],
           :"mp-slug" => 'this-is-the-content-slug',
           'syndicate-to' => 'https://myfavoritesocialnetwork.example/lildude',
           :unrecog_param => 'foo',
           :ano_unrecog_param => 'bar'
         })
    assert last_response.body.include? 'invalid_repo'
    refute last_response.created?
  end

  def test_new_note_with_syndication_everything_and_unrecognised_params
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
           'mp-slug' => 'this-is-the-content-slug',
           'syndicate-to' => 'https://myfavoritesocialnetwork.example/lildude',
           :unrecog_param => 'foo',
           :ano_unrecog_param => 'bar'
         })
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? "tags:\n- tag1\n- tag2\n"
    assert last_response.body.include? 'permalink: "this-is-the-content-slug"'
    assert last_response.body.include? "date: #{now}"
    assert last_response.body.include? 'This is the content'
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-the-content-slug", last_response.header['Location']
  end

  # Micropub.rocks tests: 100, 101
  def test_new_entry
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
         })
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-a-post", last_response.header['Location']
    assert last_response.body.include? "tags:\n- tag1\n- tag2"
  end

  # TODO: Not sure this works yet.
  def test_new_entry_with_mp_destination
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub', {
           'mp-destination' => 'testsite',
           :h => 'entry',
           :name => 'This is a 😍 Post!!',
           :content => 'This is the content',
           :category => %w[tag1 tag2],
           'syndicate-to' => 'https://myfavoritesocialnetwork.example/lildude'
         })
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-a-post", last_response.header['Location']
  end

  def test_new_note_with_title_in_markdown_content_becomes_article
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub/testsite', {
           h: 'entry',
           content: "# This is a 😍 Post!!\n\nThis is the content",
           category: %w[tag1 tag2]
         })
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got \n#{last_response.header}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-a-post", last_response.header['Location'], "Expected Location header of: https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-a-post but got \n#{last_response.header}"
    assert last_response.body.include?('tag1'), "Expected body to include tag 'tag1' but got \n#{last_response.body}"
    assert last_response.body.include?('tag2'), "Expected body to include tag 'tag2' but got \n#{last_response.body}"
    assert last_response.body.include?('This is a 😍 Post!!'), "Expected body to include 'This is a 😍 Post!!' but got \n#{last_response.body}"
    assert last_response.body.include?('This is the content'), "Expected body to include 'This is the content' but got \n#{last_response.body}"
  end

  def test_new_note_with_photo_reference
    stub_get_photo
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
           h: 'entry',
           content: 'Adding a new photo',
           photo: 'https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg'
         })
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    refute last_response.body.include? '/img/12716713_162835967431386_291746593_n.jpg'
    assert_match(%r{img/[0-9a-f]{12}\.jpg}, last_response.body)
  end

  def test_delete_post
    stub_github_search
    stub_get_github_request
    stub_get_pages_branch
    # Explicitly mock so we can confirm we're getting the modified content as expected
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with(has_entry(fm_published: 'false'))
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
           action: 'delete',
           url: 'https://example.com/2010/01/this-is-a-test-post/'
         })
    assert last_response.no_content?, "Expected 204 but got #{last_response.status}"
  end

  def test_undelete_post
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
    # Explicitly stub so we can confirm we're not getting the fm_published key
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with(Not(has_key(:fm_published)))
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
           action: 'undelete',
           url: 'https://example.com/2010/01/this-is-a-test-post/'
         })
    assert last_response.no_content?, "Expected 204 but got #{last_response.status}"
  end
end
