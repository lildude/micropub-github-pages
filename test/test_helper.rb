ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'webmock/minitest'
require_relative '../micropub-github-pages'

WebMock.disable_net_connect!(:allow_localhost => true)

def stub_token
  stub_request(:get, "http://example.com/micropub/token").
    with(:headers => {'Authorization'=>'Bearer 1234567890', 'Content-Type'=>'application/x-www-form-urlencoded'}).
    to_return(:status => 200, :body => URI.encode_www_form({
      :me => "https://testsite.example.com",
      :issued_by => "http://localhost:4567/micropub/token",
      :client_id => "http://testsite.example.com",
      :issued_at => "123456789",
      :scope => "post",
      :nonce => "0987654321"
      }))
end

def stub_get_github_request
  stub_request(:get, "https://api.github.com/repos/lildude/testsite.github.io").
    to_return(:status => 200, :body => "{ json here }")
end

def stub_put_github_request
  stub_request(:put, /api.github.com\/repos\/lildude\/testsite.github.io\/contents\/_posts\/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9].*\.md/).
    to_return(:status => 201, :body => "{ json here }")
end
