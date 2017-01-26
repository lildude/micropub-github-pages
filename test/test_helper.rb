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

def stub_noscope_token_response
  stub_request(:get, "http://example.com/micropub/token").
    with(:headers => {'Authorization'=>'Bearer 1234567890', 'Content-Type'=>'application/x-www-form-urlencoded'}).
    to_return(:status => 200, :body => URI.encode_www_form({
      :me => "https://testsite.example.com",
      :issued_by => "http://localhost:4567/micropub/token",
      :client_id => "http://testsite.example.com",
      :issued_at => "123456789",
      :nonce => "0987654321"
  }))
end

def stub_unauthed_token
  stub_request(:get, "http://example.com/micropub/token").
    with(:headers => {'Authorization'=>'Bearer 1234567890', 'Content-Type'=>'application/x-www-form-urlencoded'}).
    to_return(:status => 401, :body => URI.encode_www_form({
      :me => "https://testsite.example.com",
      :issued_by => "http://localhost:4567/micropub/token",
      :client_id => "http://testsite.example.com",
      :issued_at => "123456789",
      :scope => "post",
      :nonce => "0987654321"
  }))
end

def stub_get_github_request
  stub_request(:get, "https://api.github.com/repos/lildude/micropub-github-pages").
    to_return(:status => 200, :body => "{ json here }")
end

def stub_put_github_request
  stub_request(:put, /api.github.com\/repos\/lildude\/micropub-github-pages\/contents\/.*\/.*\.[a-z]{2,}/).
    to_return(:status => 201, :body => "{ json here }")
end

def stub_get_photo
  stub_request(:get, /scontent.cdninstagram.com\/t51.2885-15\/e35\/12716713_162835967431386_291746593_n.jpg/).
    to_return(:status => 200, :body => open("test/fixtures/photo.jpg", "rb"))
end

def stub_non_existant_github_file
  stub_request(:get, /api.github.com\/repos\/lildude\/micropub-github-pages\/contents\/media\/12716713_162835967431386_291746593_n.jpg/).
    to_return(:status => 404, :body => '404 - Not Found')
end

def stub_existing_github_file
  stub_request(:get, /api.github.com\/repos\/lildude\/micropub-github-pages\/contents\/media\/12716713_162835967431386_291746593_n.jpg/).
    to_return(:status => 200, :body => '{  "sha": "3d21ec53a331a6f037a91c368710b99387d012c1" }') # We don't need the rest of the info from the response, yet.
end
