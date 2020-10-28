# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__

class Json < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    stub_token
  end

  def test_new_note_json_syntax
    stub_get_github_request
    stub_get_pages_branch
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
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-the-json-content", last_response.header['Location']
    assert last_response.body.include? 'tag1'
    assert last_response.body.include? 'tag2'
    assert last_response.body.include? 'This is the JSON content'
  end

  def test_new_note_json_syntax_with_hashtags
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    now = Time.now
    post('/micropub/testsite', {
      type: ['h-entry'],
      properties: {
        content: ['This is the JSON content #tag1 #tag2 end.']
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert_equal "https://example.com/#{now.strftime('%Y')}/#{now.strftime('%m')}/this-is-the-json-content", last_response.header['Location']
    assert last_response.body.include? "tags:\n- tag1\n- tag2"
    assert last_response.body.include? 'This is the JSON content end.'
  end

  def test_new_note_with_html_json
    stub_get_github_request
    stub_get_pages_branch
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
    stub_get_github_request
    stub_get_pages_branch
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
    assert last_response.body.include? "tags:\n- tag1\n- tag2\n"
    assert last_response.body.include?('title: This is the header'), "Expected title to include 'This is the header', but got\n#{last_response.body}"
    refute last_response.body.include? '# This is the header'
    assert last_response.body.include? 'This is the JSON content'
  end

  def test_new_note_with_title_in_markdown_and_name_becomes_article_with_name_as_title
    stub_get_github_request
    stub_get_pages_branch
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
    assert last_response.body.include? "tags:\n- tag1\n- tag2\n"
    assert last_response.body.include?('title: This is the title'), "Expected title to include 'This is the title', but got\n#{last_response.body}"
    assert last_response.body.include? '# This is the header'
    assert last_response.body.include? 'This is the JSON content'
  end

  def test_new_note_with_photo_reference_json
    stub_get_photo
    stub_get_github_request
    stub_get_pages_branch
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
    stub_cant_get_photo
    stub_get_github_request
    stub_get_pages_branch
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
    stub_get_photo
    stub_get_github_request
    stub_get_pages_branch
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
    stub_get_photo
    stub_get_github_request
    stub_get_pages_branch
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
    stub_get_github_request
    stub_get_pages_branch
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

  def test_update_property
    stub_github_search
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    # Explicitly stub so we can confirm we're getting the modified category entries and no change to the slug
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with(
                          has_entries(
                            content: 'This is the updated text. If you can see this you passed the test!',
                            slug: '/2010/01/this-is-a-test-post'
                          )
                        )
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
      action: 'update',
      url: 'https://example.com/2010/01/this-is-a-test-post/',
      replace: {
        content: ['This is the updated text. If you can see this you passed the test!']
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.no_content?, "Expected 204 but got #{last_response.status}"
  end

  def test_add_to_property
    stub_github_search
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    # Explicitly stub so we can confirm we're getting the category modified
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with(has_entry(category: %w[foo bar tag99]))
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
      action: 'update',
      url: 'https://example.com/2010/01/this-is-a-test-post/',
      add: {
        category: ['tag99']
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.no_content?, "Expected 204 but got #{last_response.status}"
  end

  def test_add_to_non_existent_property
    stub_github_search
    # Stub a specific response without any tags/categories
    Sinatra::Application.any_instance.expects(:get_post)
                        .returns(
                          { type: ['h-entry'],
                            properties: {
                              published: ['2017-01-20 10:01:48 +0000'],
                              content: ['Micropub update test.']
                            } }
                        )
    stub_get_pages_branch
    stub_post_github_request
    # Explicitly stub so we can confirm we're getting the category property added
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with(has_entry(category: ['tag99']))
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
      action: 'update',
      url: 'https://example.com/2010/01/this-is-a-test-post/',
      add: {
        category: ['tag99']
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.no_content?, "Expected 204 but got #{last_response.status}"
  end

  def test_remove_value_from_property
    stub_github_search
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    # Explicitly mock so we can confirm we're getting the modified content as expected
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with({
                                type: :article,
                                path: '_post/2010-01-14-example-post.md',
                                url: 'https://example.com/2010/01/this-is-a-test-post/',
                                h: 'entry',
                                name: 'This is a Test Post',
                                published: '2010-01-14 10:01:48 +0000',
                                content: "This is a test post with:\n\n- Tags,\n- a permalink\n- and some **bold** and __italic__ markdown",
                                slug: '/2010/01/this-is-a-test-post',
                                category: %w[foo]
                              })
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
      action: 'update',
      url: 'https://example.com/2010/01/this-is-a-test-post/',
      delete: {
        category: ['bar']
      }
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.no_content?, "Expected 204 but got #{last_response.status}"
  end

  def test_remove_property
    stub_github_search
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    # Explicitly stub so we can confirm the category propery has been removed
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with(Not(has_key(:category)))
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
      action: 'update',
      url: 'https://example.com/2010/01/this-is-a-test-post/',
      delete: [
        'category'
      ]
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.no_content?, "Expected 204 but got #{last_response.status}"
  end

  def test_action_operation_is_valid
    # foobar is not a valid action
    post('/micropub/testsite', {
      action: 'foobar'
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.body.include?('invalid_request')
    # update operation must be present
    post('/micropub/testsite', {
      action: 'update'
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.body.include? 'invalid_request'
    # update operation must be add, replace or delete
    post('/micropub/testsite', {
      action: 'update',
      foobar: {}
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.body.include? 'invalid_request'
    # update operation must be an Enumerable
    post('/micropub/testsite', {
      action: 'update',
      delete: 'foo'
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.body.include? 'invalid_request'
  end

  def test_delete_post
    stub_github_search
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    # Explicitly stub so we can confirm we're getting the fm_published key
    Sinatra::Application.any_instance.expects(:publish_post)
                        .with(has_entry(fm_published: 'false'))
                        .returns(true) # We don't care about the status
    post('/micropub/testsite', {
      action: 'delete',
      url: 'https://example.com/2010/01/this-is-a-test-post/'
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.no_content?, "Expected 204 but got #{last_response.status}"
  end

  def test_undelete_post_json
    stub_github_search
    # Stub a specific response with fm_published: false
    Sinatra::Application.any_instance.expects(:get_post)
                        .returns(
                          { type: ['h-entry'],
                            properties: {
                              published: ['2010-01-14 10:01:48 +0000'],
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
      url: 'https://example.com/2010/01/this-is-a-test-post/'
    }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.no_content?, "Expected 204 but got #{last_response.status}"
  end
end
