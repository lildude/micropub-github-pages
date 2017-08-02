# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'webmock/minitest'
require_relative '../micropub-github-pages'

WebMock.disable_net_connect!(allow_localhost: true)

def stub_token
  stub_request(:get, 'http://example.com/micropub/token')
    .with(headers: { 'Authorization' => 'Bearer 1234567890', 'Content-Type' => 'application/x-www-form-urlencoded' })
    .to_return(status: 200, body: URI.encode_www_form(me: 'https://testsite.example.com',
                                                      issued_by: 'http://localhost:4567/micropub/token',
                                                      client_id: 'http://testsite.example.com',
                                                      issued_at: '123456789',
                                                      scope: 'post',
                                                      nonce: '0987654321'))
end

def stub_noscope_token_response
  stub_request(:get, 'http://example.com/micropub/token')
    .with(headers: { 'Authorization' => 'Bearer 1234567890', 'Content-Type' => 'application/x-www-form-urlencoded' })
    .to_return(status: 200, body: URI.encode_www_form(me: 'https://testsite.example.com',
                                                      issued_by: 'http://localhost:4567/micropub/token',
                                                      client_id: 'http://testsite.example.com',
                                                      issued_at: '123456789',
                                                      nonce: '0987654321'))
end

def stub_unauthed_token
  stub_request(:get, 'http://example.com/micropub/token')
    .with(headers: { 'Authorization' => 'Bearer 1234567890', 'Content-Type' => 'application/x-www-form-urlencoded' })
    .to_return(status: 401, body: URI.encode_www_form(me: 'https://testsite.example.com',
                                                      issued_by: 'http://localhost:4567/micropub/token',
                                                      client_id: 'http://testsite.example.com',
                                                      issued_at: '123456789',
                                                      scope: 'post',
                                                      nonce: '0987654321'))
end

def stub_get_github_request
  stub_request(:get, 'https://api.github.com/repos/lildude/micropub-github-pages')
    .to_return(status: 200, body: '{ json here }')
end

def stub_put_github_request
  stub_request(:put, %r{api.github.com\/repos\/lildude\/micropub-github-pages\/contents\/.*\/.*\.[a-z]{2,}})
    .to_return(status: 201, body: '{ json here }')
end

def stub_get_photo
  stub_request(:get, %r{.*instagram.*\/t51.2885-15\/e35\/\d+_\d+_\d+_n.jpg})
    .to_return(status: 200, body: open('test/fixtures/photo.jpg', 'rb'))
end

def stub_cant_get_photo
  stub_request(:get, %r{.*instagram.*\/t51.2885-15\/e35\/\d+_\d+_\d+_nope.jpg})
    .to_return(status: 404, body: '')
end

def stub_non_existant_github_file
  stub_request(:get, %r{api.github.com\/repos\/lildude\/micropub-github-pages\/contents\/.*\/\d+_\d+_\d+_n.jpg})
    .to_return(status: 404, body: '404 - Not Found')
end

def stub_existing_github_file
  stub_request(:get, %r{api.github.com\/repos\/lildude\/micropub-github-pages\/contents})
    .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: JSON.generate(sha: 'd735c3364cacbda4a9631af085227ce200589676',
                                                                                                   content: 'LS0tDQpsYXlvdXQ6IHBvc3QNCnRpdGxlOiAgVGhpcyBpcyBhIFRlc3QgUG9zdA0KZGF0ZTogICAyMDE3LTAxLTIwIDEwOjAxOjQ4DQp0YWdzOiANCi0gZm9vIA0KLSBiYXINCnBlcm1hbGluazogLzIwMTcvMDEvdGhpcy1pcy1hLXRlc3QtcG9zdA0KLS0tDQoNClRoaXMgaXMgYSB0ZXN0IHBvc3Qgd2l0aDoNCg0KLSBUYWdzLA0KLSBhIHBlcm1hbGluaw0KLSBhbmQgc29tZSAqKmJvbGQqKiBhbmQgX19pdGFsaWNfXyBtYXJrZG93bg=='))
end

def stub_github_search
  stub_request(:get, %r{api.github.com/search/code})
    .to_return(status: 200, body: JSON.generate(total_count: 1,
                                                items: [
                                                  {
                                                    name: 'example-post.md',
                                                    path: '_post/2010-01-14-example-post.md',
                                                    sha: 'd735c3364cacbda4a9631af085227ce200589676'
                                                  }
                                                ]))
end

def stub_silo_pub
  stub_request(:post, 'https://silo.pub/micropub')
    .with(body: { content: /.*/, url: /.*/ }, headers: { 'Authorization' => 'Bearer 0987654321', 'Content-Type' => 'application/x-www-form-urlencoded' })
    .to_return(status: 200, body: '{"id_str": "12344321"}', headers: {})
end
