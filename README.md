# Micropub to GitHub Pages

![Tests Status Badge](https://github.com/lildude/micropub-github-pages/workflows/Tests/badge.svg) ![Linters Status Badge](https://github.com/lildude/micropub-github-pages/workflows/Linters/badge.svg) [![codecov](https://codecov.io/gh/lildude/micropub-github-pages/branch/main/graph/badge.svg?token=C2W0HNSM5Q)](https://codecov.io/gh/lildude/micropub-github-pages)

A Micropub server that accepts [Micropub](http://micropub.net/) requests and creates and publishes a Jekyll/GitHub Pages post to a configured GitHub repository. This server supports posting to multiple sites from the same server. This project is inspired by [Micropub to GitHub](https://github.com/voxpelli/webpage-micropub-to-github), a Node.js implementation.

## Run on Heroku

TBC

<!--
Clicky this button :point_right: [![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy?template=https://github.com/lildude/micropub-github-pages) :soon:. It doesn't work just yet.
-->

## Running Elsewhere or Locally

Clone the repository and run `bundle install`.

Run `GITHUB_ACCESS_TOKEN="your_personal_access_token" bundle exec rackup` and you'll have the application running on <http://localhost:9292> .

Alternatively, create an `env.rb` file in the root of this repository containing: `ENV['GITHUB_ACCESS_TOKEN'] = 'your_personal_access_token'`.

## Configuration

Copy `config-example.yml` to `config.yml` and customise to your :heart:'s content. See the [configuration docs](docs/configuration.md) for full details.

## Customise Posts Layouts

You can customise the layout and format of your posts by modifying the templates in the `templates/` directory. These are written in Liquid like Jekyll themes.

## Syndication

Syndication is available via [Brid.gy](https://brid.gy/).

## Testing

Run `bundle exec rake test` to run through the full test suite and `bundle exec rake standard` for [Standard](https://github.com/testdouble/standard) linting.

## Contributing

Want to contribute to this project? Great! Fork the repo, make your changes (don't forget to add tests 😉) and submit a pull request.

## License

## Micropub.rocks Validation Tests

I'm using a local instance of <https://micropub.rocks> ([my fork](https://github.com/lildude/micropub.rocks) has better setup instructions than upstream - I plan to dockerise it too) to test my implimentation as I progress and this is the progress so far:

### Creating Posts (Form-Encoded)

✅ 100 Create an h-entry post (form-encoded)  
✅ 101 Create an h-entry post with multiple categories (form-encoded)  
✅ 104 Create an h-entry with a photo referenced by URL (form-encoded)  
✅ 107 Create an h-entry post with one category (form-encoded)  

### Creating Posts (JSON)

✅ 200 Create an h-entry post (JSON)  
✅ 201 Create an h-entry post with multiple categories (JSON)  
✅ 202 Create an h-entry with HTML content (JSON)  
✅ 203 Create an h-entry with a photo referenced by URL (JSON)  
✅ 204 Create an h-entry post with a nested object (JSON)  
✅ 205 Create an h-entry post with a photo with alt text (JSON)  
✅ 206 Create an h-entry with multiple photos referenced by URL (JSON)  

### Creating Posts (Multipart)

✅ 300 Create an h-entry with a photo (multipart)  
✅ 301 Create an h-entry with two photos (multipart)  

### Updates

✅ 400 Replace a property  
✅ 401 Add a value to an existing property  
✅ 402 Add a value to a non-existent property  
✅ 403 Remove a value from a property  
✅ 404 Remove a property  
✅ 405 Reject the request if operation is not an array  

### Deletes

✅ 500 Delete a post (form-encoded)  
✅ 501 Delete a post (JSON)  
✅ 502 Undelete a post (form-encoded)  
✅ 503 Undelete a post (JSON)  

**Note** Deleting doesn't remove the post, it adds/removes the `published` property from the post's frontmatter.

### Query

✅ 600 Configuration Query  
✅ 601 Syndication Endpoint Query  
✅ 602 Source Query (All Properties)  
✅ 603 Source Query (Specific Properties)

### Media Endpoint

✅ 700 Upload a jpg to the Media Endpoint  
✅ 701 Upload a png to the Media Endpoint  
✅ 702 Upload a gif to the Media Endpoint  

### Authentication

✅ 800 Accept access token in HTTP header  
✅ 801 Accept access token in POST body  
✅ 802 Does not store access token property  
✅ 803 Rejects unauthenticated requests  
✅ 804 Rejects unauthorized access tokens

---

### TODOs

- [ ] Use GitHub App for access instead of PAT
- [ ] Dockerise
