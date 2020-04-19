# Micropub to GitHub Pages

![](https://github.com/lildude/micropub-github-pages/workflows/Tests/badge.svg) ![](https://github.com/lildude/micropub-github-pages/workflows/Linters/badge.svg) [![Coverage Status](https://coveralls.io/repos/github/lildude/micropub-github-pages/badge.svg)](https://coveralls.io/github/lildude/micropub-github-pages)

A simple Micropub server that accepts [Micropub](http://micropub.net/) requests and creates and publishes a Jekyll/GitHub Pages post to a configured GitHub repository.  This project is inspired by [Micropub to GitHub](https://github.com/voxpelli/webpage-micropub-to-github), a Node.js implementation.

## Setup

[Scripts to Rule Them All](http://githubengineering.com/scripts-to-rule-them-all/) is part of my day-to-day job and I really like the idea, so that's what I use here too.

Just run `script/bootstrap` and you're get all the gem bundle goodness happening for you.

### Heroku

TBC

<!--
Clicky this button :point_right: [![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy?template=https://github.com/lildude/micropub-github-pages) :soon:. It doesn't work just yet.
-->

### Elsewhere

Run `GITHUB_ACCESS_TOKEN=[your_personal_access_token] script/server` and you'll have the application running on http://localhost:9292 .

Alternatively, create an `env.rb` file in the root of this repository containing: `ENV['GITHUB_ACCESS_TOKEN'] = '[your_personal_access_token]'`.

## Configuration

Copy `config-example.yml` to `config.yml` and customise to your :heart:'s content.

## Syndication

TBC

## Testing

Run `script/test` to run through the full test suite.

## License

Micropub to GitHub Pages is licensed under the MIT License.

---

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

- [ ] 400 Replace a property  
- [ ] 401 Add a value to an existing property  
- [ ] 402 Add a value to a non-existent property  
- [ ] 403 Remove a value from a property  
- [ ] 404 Remove a property  
- [ ] 405 Reject the request if operation is not an array  

### Deletes

- [ ] 500 Delete a post (form-encoded)  
- [ ] 501 Delete a post (JSON)  
- [ ] 502 Undelete a post (form-encoded)  
- [ ] 503 Undelete a post (JSON)  

### Query

✅ 600 Configuration Query  
✅ 601 Syndication Endpoint Query  
✅ 602 Source Query (All Properties)  
✅ 603 Source Query (Specific Properties) <small>* this only passes because we currently return everything and the test doesn't check for requested properties.</small>  

### Media Endpoint

- [ ] 700 Upload a jpg to the Media Endpoint  
- [ ] 701 Upload a png to the Media Endpoint  
- [ ] 702 Upload a gif to the Media Endpoint  

### Authentication

✅ 800 Accept access token in HTTP header  
✅ 801 Accept access token in POST body  
✅ 802 Does not store access token property  
✅ 803 Rejects unauthenticated requests  
- [ ] 804 Rejects unauthorized access tokens <small>* I think this passes, but holding off checkig until 💯</small>  

---

### TODOs

- [ ] Determine pages branch via API or use override if using repo but not Pages
- [ ] Add integration tests from micropub.rocks
- [ ] Use GitHub App for access instead of PAT
- [ ] Dockerise

