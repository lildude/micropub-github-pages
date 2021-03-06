# frozen_string_literal: true

require "sucker_punch/testing/inline"
require File.expand_path "test_helper.rb", __dir__

class BridgyJobTest < Minitest::Test
  def test_perform_success_with_defaults
    stub_get_published_page
    stub_request(:post, "https://brid.gy/publish/webmention?bridgy_ignore_formatting=false&bridgy_omit_link=false")
      .with(body: "source=https%3A%2F%2Fexample.com%2F2020%2F01%2Fthis-is-a-test-post%2F&target=https%3A%2F%2Fbrid.gy%2Fpublish%2Ftwitter")
      .to_return(status: 201)
    out, = capture_subprocess_io do
      BridgyJob.perform_async("https://example.com/2020/01/this-is-a-test-post/", "twitter")
    end
    assert_match(/Successfully/, out)
  end

  def test_perform_success_with_options
    stub_get_published_page
    stub_request(:post, "https://brid.gy/publish/webmention?bridgy_ignore_formatting=true&bridgy_omit_link=maybe")
      .with(body: "source=https%3A%2F%2Fexample.com%2F2020%2F01%2Fthis-is-a-test-post%2F&target=https%3A%2F%2Fbrid.gy%2Fpublish%2Ftwitter")
      .to_return(status: 201)
    out, = capture_subprocess_io do
      BridgyJob.perform_async("https://example.com/2020/01/this-is-a-test-post/", "twitter", bridgy_omit_link: "maybe", bridgy_ignore_formatting: true)
    end
    assert_match(/Successfully/, out)
  end

  def test_perform_success_on_multiple_attempts
    stub_request(:head, %r{example.com/}).to_return(status: 404)
    stub_get_published_page
    stub_request(:post, %r{brid.gy/publish/webmention}).to_return(status: 201)
    out, = capture_subprocess_io do
      BridgyJob.perform_async("https://example.com/2020/01/this-is-a-test-post/", "twitter")
    end
    assert_match(/Successfully/, out)
  end

  def test_perform_post_never_appears
    stub_request(:head, %r{example.com/}).to_return(status: 404)
    out, = capture_subprocess_io do
      BridgyJob.perform_async("https://example.com/2020/01/this-is-a-test-post/", "twitter")
    end
    assert_match(/No syndication attempted/, out)
  end

  def test_perform_bridgy_is_not_happy
    stub_request(:head, %r{example.com/}).to_return(status: 404)
    stub_get_published_page
    stub_request(:post, %r{brid.gy/publish/webmention}).to_return(status: 500)
    out, = capture_subprocess_io do
      BridgyJob.perform_async("https://example.com/2020/01/this-is-a-test-post/", "twitter")
    end
    assert_match(/Bridgy not happy: 500/, out)
  end
end
