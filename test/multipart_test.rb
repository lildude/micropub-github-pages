# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__

class Multipart < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    stub_token
  end

  def test_new_entry_with_photo_multipart
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    photo = Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), 'fixtures', 'photo.jpg'))
    post('/micropub/testsite', {
           h: 'entry',
           content: 'Adding a new photo',
           photo: photo
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include?('/img/')
  end

  def test_new_entry_with_two_photos_multipart
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    photo = [
      Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), 'fixtures', 'photo.jpg')),
      Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), 'fixtures', 'photo2.jpg'))
    ]
    post('/micropub/testsite', {
           h: 'entry',
           content: 'Adding a new photo',
           photo: photo
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include?('/img/photo.jpg')
    assert last_response.body.include?('/img/photo2.jpg')
  end

  # This test is specific to the mp-photo-alt attribute micro.blog uses for images with descriptions
  def test_new_entry_with_two_photos_multipart_with_alt
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    post('/micropub/testsite', {
           h: 'entry',
           content: 'Adding a new photo',
           photo: ['https://example.com/img/photo.jpg', 'https://example.com/img/photo2.jpg'],
           "mp-photo-alt": ['Alt 1', 'Alt 2']
         }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    assert last_response.body.include?('![Alt 1](https://example.com/img/photo.jpg)')
    assert last_response.body.include?('![Alt 2](https://example.com/img/photo2.jpg)')
  end

  def test_media_upload
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    media = Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), 'fixtures', 'photo.jpg'), 'image/jpeg')

    post('/micropub/testsite/media', { file: media }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    refute last_response.header.include?('photo.jpg')
  end

  def test_media_upload_ensure_image_jpg
    stub_get_github_request
    stub_get_pages_branch
    stub_post_github_request
    stub_patch_github_request
    media = Rack::Test::UploadedFile.new(File.join(File.dirname(__FILE__), 'fixtures', 'image.jpg'), 'image/jpeg')

    post('/micropub/testsite/media', { file: media }, 'HTTP_AUTHORIZATION' => 'Bearer 1234567890')
    assert last_response.created?, "Expected 201 but got #{last_response.status}"
    assert last_response.header.include?('Location'), "Expected 'Location' header, but got #{last_response.header}"
    refute_match 'image.jpg', last_response.header['Location']
  end
end
