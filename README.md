# Micropub to GitHub Pages

![Tests Status Badge](https://github.com/lildude/micropub-github-pages/workflows/Tests/badge.svg) ![Linters Status Badge](https://github.com/lildude/micropub-github-pages/workflows/Linters/badge.svg) [![codecov](https://codecov.io/gh/lildude/micropub-github-pages/branch/main/graph/badge.svg?token=C2W0HNSM5Q)](https://codecov.io/gh/lildude/micropub-github-pages)

A Micropub server that accepts [Micropub](http://micropub.net/) requests and creates and publishes a Jekyll/GitHub Pages post to a configured GitHub repository. This server supports posting to multiple sites from the same server. This project is inspired by [Micropub to GitHub](https://github.com/voxpelli/webpage-micropub-to-github), a Node.js implementation.

## Run on Heroku

Fork this repo, [configure](#configuration) and then clicky this button :point_right: [![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

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

Micropub to GitHub Pages is licensed under the MIT License.
