# frozen_string_literal: true

require File.expand_path 'test_helper.rb', __dir__

class Helpers < Minitest::Test
  def helpers
    Class.new { include AppHelpers }
  end

  def setup
    @helper = helpers.new
  end

  def test_verify_token_valid
    stub_token
    @helper.instance_variable_set(:@access_token, '1234567890')
    result = @helper.verify_token
    assert_equal %w[create update delete undelete], result
  end

  def test_jekyll_post
    content = "---\nlayout: post\ntags:\n- tag1\n- tag2\npermalink: \"/2017/07/foo-bar\"\ndate: 2017-07-22 10:56:22 +0100\nfoo: \"bar\"\n---\nThis is the content"
    jekyll_hash = { type: ['h-entry'], properties: { published: ['2017-07-22 10:56:22 +0100'], content: ['This is the content'], slug: ['/2017/07/foo-bar'], category: %w[tag1 tag2], fm_foo: ['bar'] } }
    assert_equal jekyll_hash, @helper.jekyll_post(content)
  end

  def test_create_slug
    assert_equal 'this-is-a-slug', @helper.create_slug("mp-slug": 'this-is-a-slug')
    assert_equal 'this-is-a-slug', @helper.create_slug("mp-slug": 'this is a slug')
    assert_equal 'foobar', @helper.create_slug("mp-slug": '/2017/07/foobar')
    assert_equal 'foobar', @helper.create_slug("mp-slug": '/2017/07/foobar/')
    assert_equal 'this-is-a-name-slug', @helper.create_slug(name: 'This is a name 😜 Slug')
    assert_equal 'this-is-1234-no-emoji-or-punc', @helper.create_slug(name: 'this is 🍎 1234 no Emoji ! or punc')
    assert_equal 'this-ends-in-emoji', @helper.create_slug(name: 'tHis ends In emoji 🤡')
    assert_equal 'no-triple-dots', @helper.create_slug(name: 'no… triple … dots…')
    assert_equal 'this-is-the-title', @helper.create_slug(title: 'This is The TITLE')
    assert_equal 'slug-from-the-first-five', @helper.create_slug(content: 'Slug 😄 from   the first five words')
    assert_equal 'all-extra-spaces-removed', @helper.create_slug(content: 'all  extra    spaces-removed')
    assert_equal 'no-dup-hyphens', @helper.create_slug(content: 'no -🥵- dup hyphens')
    assert_equal 'no-tags', @helper.create_slug(content: 'no #hash tags')
    assert_equal '35782', @helper.create_slug(published: '2017-07-02 02:56:22 -0700')
    assert_equal 'first-three-words', @helper.create_slug(content: "First Three Words\n\nSecond three words")
    assert_equal 'this-post-has-bold-and', @helper.create_slug(content: '<p>This post has <b>bold</b> and <i>italic</i> text.</p>')
  end

  def test_create_permalink
    params = {
      permalink_style: '/:categories/:year/:month/:i_month/:day/:i_day/:short_year/:hour/:minute/:second/:title',
      'mp-slug': 'foo-bar',
      published: '2017-07-02 02:56:22 -0700'
    }
    assert_equal '/2017/07/7/02/2/17/02/56/22/foo-bar', @helper.create_permalink(params)
  end

  def test_syndicate_to_get
    skip 'Not implemented'
    output = JSON.parse(@helper.syndicate_to)
    assert output.include? 'syndicate-to'
    assert_equal 'Twitter', output['syndicate-to'][0]['name']
    assert_equal 'https://twitter.com/lildude', output['syndicate-to'][0]['uid']
    refute output['syndicate-to'][0].include? 'silo_pub_token'
  end

  def test_syndicate_note
    skip 'Not implemented'
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
    assert_equal :note, @helper.post_type(h: 'entry', name: '', content: 'foo')
    assert_equal :dump_all, @helper.post_type(h: 'entry', ano: 'foo')
    assert_equal :event, @helper.post_type(h: 'event', content: 'foo')
    assert_equal :cite, @helper.post_type(h: 'cite', content: 'foo')
    assert_equal :photo, @helper.post_type(h: 'entry', photo: 'foo')
  end
end
