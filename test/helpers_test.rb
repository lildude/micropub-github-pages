# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__

class HelpersTest < Minitest::Test
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

  def test_verify_token_valid
    skip
    stub_token
    @helper.instance_variable_set(:@access_token, '1234567890')
    result = @helper.verify_token
    assert result.include? :me
    assert result.include? :issued_by
    assert result.include? :client_id
    assert_equal 'https://testsite.example.com', result[:me]
  end

  def test_jekyll_post
    content = "---\nlayout: post\ntags:\n- tag1\n- tag2\npermalink: \"/2017/07/foo-bar\"\ndate: 2017-07-22 10:56:22 +0100\nfoo: \"bar\"\n---\nThis is the content"
    jekyll_hash = { type: ['h-entry'], properties: { published: ['2017-07-22 10:56:22 +0100'], content: ['This is the content'], slug: ['/2017/07/foo-bar'], category: %w[tag1 tag2], fm_foo: ['bar'] } }
    assert_equal jekyll_hash, @helper.jekyll_post(content)
  end

  def test_create_slug
    assert_equal 'this-is-a-slug', @helper.create_slug(slug: 'this-is-a-slug')
    assert_equal 'foobar', @helper.create_slug(slug: '/2017/07/foobar')
    assert_equal 'foobar', @helper.create_slug(slug: '/2017/07/foobar/')
    assert_equal 'this-is-a-name-slug', @helper.create_slug(name: 'This is a name 😜 Slug')
    assert_equal '35782', @helper.create_slug(published: '2017-07-02 02:56:22 -0700')
  end

  def test_slugify
    assert_equal 'this-is-text', @helper.slugify('this is text')
    assert_equal 'this-is-1234-no-emoji-or-punc', @helper.slugify('this is 🍎 1234 no emoji ! or punc')
    assert_equal 'this-ends-in-emoji', @helper.slugify('tHis ends In emoji 🤡')
  end

  def test_create_permalink
    params = {
      permalink_style: '/:categories/:year/:month/:i_month/:day/:i_day/:short_year/:hour/:minute/:second/:title',
      slug: 'foo-bar',
      published: '2017-07-02 02:56:22 -0700'
    }
    assert_equal '/2017/07/7/02/2/17/02/56/22/foo-bar', @helper.create_permalink(params)
  end

  def test_syndicate_to_get
    output = JSON.parse(@helper.syndicate_to)
    assert output.include? 'syndicate-to'
    assert_equal 'Twitter', output['syndicate-to'][0]['name']
    assert_equal 'https://twitter.com/lildude', output['syndicate-to'][0]['uid']
    refute output['syndicate-to'][0].include? 'silo_pub_token'
  end

  def test_syndicate_note
    stub_silo_pub
    @helper.instance_variable_set(:@content, 'this is the content')
    @helper.instance_variable_set(:@location, 'http://example.com/2010/01/14/12345')
    params = { 'syndicate-to': ['https://twitter.com/lildude'], content: 'this is the content' }
    assert_equal '12344321', @helper.syndicate_to(params)
    assert_nil @helper.syndicate_to({})
    assert_nil @helper.syndicate_to('syndicate-to': '')
  end

  def test_post_type
    assert_equal :article, @helper.post_type(h: 'entry', name: 'foo', content: 'foo')
    assert_equal :reply, @helper.post_type(h: 'entry', in_reply_to: 'foo')
    assert_equal :repost, @helper.post_type(h: 'entry', repost_of: 'foo')
    assert_equal :bookmark, @helper.post_type(h: 'entry', bookmark_of: 'foo')
    assert_equal :note, @helper.post_type(h: 'entry', content: 'foo')
    assert_equal :dump_all, @helper.post_type(h: 'entry', ano: 'foo')
    assert_equal :event, @helper.post_type(h: 'event', content: 'foo')
    assert_equal :cite, @helper.post_type(h: 'cite', content: 'foo')
  end
end
