# Micropub to GitHub Pages

![Build Status](https://github.com/actions/micropub-github-pages/workflows/Continuous%20Integration/badge.svg) [![Coverage Status](https://coveralls.io/repos/github/lildude/micropub-github-pages/badge.svg)](https://coveralls.io/github/lildude/micropub-github-pages)

A simple Micropub server that accepts [Micropub](http://micropub.net/) requests and creates and publishes a Jekyll/GitHub Pages post to a configured GitHub repository.  This project is inspired by [Micropub to GitHub](https://github.com/voxpelli/webpage-micropub-to-github), a Node.js implementation.

## Setup

[Scripts to Rule Them All](http://githubengineering.com/scripts-to-rule-them-all/) is part of my day-to-day job and I really like the idea, so that's what I use here too.

Just run `script/bootstrap` and you're get all the gem bundle goodness happening for you.

### Heroku

Clicky this button :point_right: [![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy?template=https://github.com/lildude/micropub-github-pages) :soon:. It doesn't work just yet.


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

### TODOs

- [ ] Determine pages branch via API or use override if using repo but not Pages
- [ ] Add integration tests from micropub.rocks
- [ ] Use GitHub App for access instead of PAT

