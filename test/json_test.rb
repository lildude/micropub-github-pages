# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__

class JsonTest < Minitest::Test
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

  def test_new_note_json_syntax
    stub_token
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        content: ['This is the JSON content'],
        category: %w[tag1 tag2]
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/#{now.strftime('%s').to_i % (24 * 60 * 60)}", last_response.header['Location']
    assert last_response.body.include? 'tag1'
    assert last_response.body.include? 'tag2'
    assert last_response.body.include? 'This is the JSON content'
  end

  def test_new_note_with_html_json
    stub_token
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        content: [{
          'html': '<p>This post has <b>bold</b> and <i>italic</i> text.</p>'
        }]
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.body.include? '<p>This post has <b>bold</b> and <i>italic</i> text.</p>'
  end

  def test_new_note_with_title_in_markdown_content_becomes_article_json
    stub_token
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        content: ["# This is the header\n\nThis is the JSON content"],
        category: %w[tag1 tag2]
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-the-header", last_response.header['Location']
    assert last_response.body.include? 'tag1'
    assert last_response.body.include? 'tag2'
    assert last_response.body.include?('title: This is the header'), "Expected title to include 'This is the header', but got\n#{last_response.body}"
    refute last_response.body.include? '# This is the header'
    assert last_response.body.include? 'This is the JSON content'
  end

  def test_new_note_with_title_in_markdown_and_name_becomes_article_with_name_as_title
    stub_token
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        name: ['This is the title'],
        content: ["# This is the header\n\nThis is the JSON content"],
        category: %w[tag1 tag2]
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-the-title", last_response.header['Location']
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
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        content: ['Adding a new photo'],
        photo: ['https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg']
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? '/img/12716713_162835967431386_291746593_n.jpg'
  end

  def test_new_note_with_unreachable_photo_reference_json
    stub_token
    stub_cant_get_photo
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        content: ['Adding a new photo'],
        photo: ['https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_nope.jpg']
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? 'https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_nope.jpg'
  end

  def test_new_note_with_multiple_photos_reference_json
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        content: ['Adding a new photo'],
        photo: ['https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg',
                'https://instagram.flhr2-1.fna.fbcdn.net/t51.2885-15/e35/13557237_1722207908037147_1805177879_n.jpg']
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include? '/img/12716713_162835967431386_291746593_n.jpg'
  end

  def test_new_note_with_photo_reference_with_alt_json
    stub_token
    stub_get_photo
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        content: ['Adding a new photo'],
        photo: [{
          value: 'https://scontent.cdninstagram.com/t51.2885-15/e35/12716713_162835967431386_291746593_n.jpg',
          alt: 'Instagram photo'
        }]
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include?('/img/12716713_162835967431386_291746593_n.jpg'), "Body contains #{last_response.body}"
    assert last_response.body.include? 'Instagram photo'
  end

  def test_h_entry_with_nested_object
    stub_token
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        summary: ['Weighed 70.64 kg'],
        "x-weight": [{
          type: ['h-measure'],
          properties: {
            num: ['70.64'],
            unit: ['kg']
          }
        }]
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/#{now.strftime('%s').to_i % (24 * 60 * 60)}", last_response.header['Location']
    assert last_response.body.include?('Weighed 70.64 kg'), "Body did not include 'Weighed 70.64 kg'\n#{last_response.body}"
    assert last_response.body.include?('70.64'), 'Body did not include "70.64"'
    assert last_response.body.include?('kg'), 'Body did not include "kg"'
  end

  def test_update_post_json
    stub_token
    stub_github_search
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
      action: 'update',
      url: 'https://example/2010/01/14/example-post/',
      replace: {
        content: ["This is the updated text. If you can see this you passed the test!"]
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"

  def test_add_to_property
    stub_token
    stub_github_search
    stub_get_github_request
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
      action: 'update',
      url: 'https://example.com/2017/01/this-is-a-test-post/',
      add: {
        category: ["tag99"]
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal 'https://example.com/2017/01/this-is-a-test-post', last_response.header['Location']
  end

  def test_delete_post_json
    skip('TODO: not yet implemented - requires update support first')
  end

  def test_undelete_post_json
    skip('TODO: not yet implemented - requires update support first')
  end
end
