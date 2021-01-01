# Configuration

Micropub to GitHub supports posting to multiple sites from a single server so you only need to deploy this once and publish to multiple destinations. Each setting can be set globally or on a per-site basis. 

The following configuration options are available:

**Required:**

These settings are all required and need to be set globally.

- `micropub_token_endpoint`: it is assumed the same auth endpoint is used for all sites.
- `sites`: Sub-section for each of the sites you want to publish to.
  - `<name>`: A short name for your site. This and the next two options are required for each site.
    - `github_repo`: The username/repo for the site.
    - `site_url`: The base URL of the site.

**Optional:**

These settings are all optional and can be set globally or on a per-site basis, with the per-site settings overriding the global options.

- `permalink_style`: [Jekyll permalink style](https://jekyllrb.com/docs/permalinks/#global) as per your site's `_config.yml`. This can be set globally and then overridden on a per-site basis.
  Default: `/:date` (Jekyll's default)
- `download_photos`: Ensure linked images are added to repo.
  Default: `false`
- `image_dir`: Directory in to which images will be saved.
  Default: `images`
- `posts_dir`: Directory in to which posts will be saved.
  Default: `_posts`
- `syndicate_to_bridgy`: Syndicate posts using [Brid.gy](https://brid.gy/).
  Default: `false`
- `bridgy_options`: Sub-section for the following options:
  - `bridgy_omit_link`: [Disable link back to post](https://brid.gy/about#omit-link).
    Options: `true|false|maybe`
    Default: `false`
  - `bridgy_ignore_formatting`: [Disable the plain text whitespace and formatting](https://brid.gy/about#ignore-formatting).
    Options: `true|false`
    Default: `false`

## Examples of Single Site Configurations

- This is a minimal single site configuration that uses all the defaults detailed above:

  ```yaml
  # config.yml
  micropub_token_endpoint: "https://indieauth.com/token"

  sites:
    mysite:
      github_repo: "user/my-website"
      site_url: "https://example.com"
  ```

- A slightly more complicated single site configuration that overrides a few of the defaults:

  ```yaml
  # config.yml
  micropub_token_endpoint: "https://indieauth.com/token"
  permalink_style: "/:title"
  image_dir: "imgs"

  sites:
    mysite:
      github_repo: "user/my-website"
      site_url: "https://example.com"
  ```

  This example behaves identically to that above:

  ```yaml
  # config.yml
  micropub_token_endpoint: "https://indieauth.com/token"

  sites:
    mysite:
      github_repo: "user/my-website"
      site_url: "https://example.com"
      permalink_style: "/:title"
      image_dir: "imgs" 
  ```

## Examples of Multi-site Configurations

- This is a minimal multi-site configuration that uses all the defaults detailed above:

  ```yaml
  # config.yml
  micropub_token_endpoint: "https://indieauth.com/token"

  sites:
    mysite:
      github_repo: "user/my-website"
      site_url: "https://my-example.com"
    anosite:
      github_repo: "user/ano-website"
      site_url: "https://ano-example.com"
  ```

- A slightly more complicated multi-site configuration that overrides a few of the defaults:

  ```yaml
  # config.yml
  micropub_token_endpoint: "https://indieauth.com/token"
  permalink_style: "/:title"
  image_dir: "imgs"

  sites:
    mysite:
      github_repo: "user/my-website"
      site_url: "https://example.com"
    anosite:
      github_repo: "user/ano-website"
      site_url: "https://ano-example.com"
      permalink_style: "/:categories/:year/:month/:title/"
      image_dir: "images"
  ```

  The `config-example.yml` file contains an example with all the defaults documented.
