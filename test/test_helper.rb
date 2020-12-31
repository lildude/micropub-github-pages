# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'simplecov'
require 'coveralls'
SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
]
SimpleCov.start do
  add_filter 'vendor'
  add_filter 'test'
end

require 'mocha/minitest'
require 'minitest/pride'
require 'minitest/autorun'
require 'rack/test'
require 'webmock/minitest'
require 'mocha/setup'
require_relative '../app'

WebMock.disable_net_connect!(allow_localhost: true)

def stub_token(scope = 'create update delete undelete')
  stub_request(:get, 'http://example.com/micropub/token')
    .with(headers: { 'Authorization' => 'Bearer 1234567890',
                     'Accept' => 'application/x-www-form-urlencoded' })
    .to_return(status: 200,
               body: URI.encode_www_form(
                 me: 'https://testsite.example.com',
                 issued_by: 'http://localhost:4567/micropub/token',
                 client_id: 'http://testsite.example.com',
                 issued_at: '123456789', scope: scope, nonce: '0987654321'
               ))
end

def stub_noscope_token_response
  stub_request(:get, 'http://example.com/micropub/token')
    .with(headers: { 'Authorization' => 'Bearer 1234567890',
                     'Accept' => 'application/x-www-form-urlencoded' })
    .to_return(status: 200,
               body: URI.encode_www_form(
                 me: 'https://testsite.example.com',
                 issued_by: 'http://localhost:4567/micropub/token',
                 client_id: 'http://testsite.example.com',
                 issued_at: '123456789', nonce: '0987654321'
               ))
end

def stub_unauthed_token
  stub_request(:get, 'http://example.com/micropub/token')
    .with(headers: { 'Authorization' => 'Bearer 1234567890',
                     'Accept' => 'application/x-www-form-urlencoded' })
    .to_return(status: 401,
               body: URI.encode_www_form(
                 me: 'https://testsite.example.com',
                 issued_by: 'http://localhost:4567/micropub/token',
                 client_id: 'http://testsite.example.com',
                 issued_at: '123456789', scope: 'post', nonce: '0987654321'
               ))
end

# Handles all GET API requests - this is a fudged reponse to satisfy all requests
# and does match an actual GitHub API response
def stub_get_github_request(code: 200, fixture: '2010-01-14-example-post.md')
  stub_request(:get, %r{api.github.com/repos/.*/micropub-github-pages})
    .to_return(
      status: code, headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(
        object: { sha: 'aa218f56b14c9653891f9e74264a383fa43fefbd' },
        commit: {
          tree: { sha: '6dcb09b5b57875f334f61aebed695e2e4193db5e' }
        },
        sha: 'd735c3364cacbda4a9631af085227ce200589676',
        content: Base64.encode64(File.read("test/fixtures/#{fixture}")),
        path: "_post/#{fixture}",
        total_count: 1,
        items: [{
          name: 'example-post.md',
          path: "_post/#{fixture}",
          sha: 'd735c3364cacbda4a9631af085227ce200589676'
        }]
      )
    )
end

def stub_get_pages_branch
  stub_request(:get, %r{api.github.com/.*/pages})
    .to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(
        source: {
          branch: 'master',
          directory: '/'
        }
      )
    )
end

def stub_post_github_request
  stub_request(:post, %r{api.github.com/repos/.*/git/.*})
    .to_return(
      status: 201, headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(
        sha: 'd735c3364cacbda4a9631af085227ce200589676'
      )
    )
end

def stub_patch_github_request
  stub_request(:patch, %r{api.github.com/repos/.*/git/.*})
    .to_return(
      status: 201, headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(
        sha: 'd735c3364cacbda4a9631af085227ce200589676'
      )
    )
end

def stub_get_photo
  stub_request(:get, %r{.*instagram.*/t51.2885-15/e35/\d+_\d+_\d+_n.jpg})
    .to_return(status: 200, body: File.open('test/fixtures/photo.jpg', 'rb'))
end

def stub_cant_get_photo
  stub_request(:get, %r{.*instagram.*/t51.2885-15/e35/\d+_\d+_\d+_nope.jpg})
    .to_return(status: 404, body: '')
end

def stub_github_search(count: 1, fixture: '2010-01-14-example-post.md')
  stub_request(:get, %r{api.github.com/search/code})
    .to_return(status: 200,
               body: JSON.generate(
                 total_count: count,
                 items: [{
                   name: 'example-post.md',
                   path: "_post/#{fixture}",
                   sha: 'd735c3364cacbda4a9631af085227ce200589676'
                 }]
               ))
end

def stub_get_published_page
  stub_request(:head, %r{example.com/}).to_return(status: 200)
end
