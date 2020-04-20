# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__

class MultipartTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_new_entry_with_photo_multipart
    stub_token
    stub_get_photo
    stub_get_github_request
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
    assert last_response.body.include?('/img/photo.jpg')
  end

  def test_new_entry_with_two_photos_multipart
    stub_token
    stub_get_photo
    stub_get_github_request
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
end
