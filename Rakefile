# frozen_string_literal: true

require 'rake/testtask'
require 'rubocop/rake_task'

task default: 'test'

Rake::TestTask.new do |t|
  ENV['SITES_CONFIG'] = '{"sites":{"testsite":{"github_repo":"lildude/micropub-github-pages","permalink_style":"/:categories/:year/:month/:title","site_url":"https://example.com","full_image_urls":false,"image_dir":"img"}},"micropub":{"token_endpoint":"http://example.com/micropub/token"},"download_photos":true,"syndicate_to":{"0":{"uid":"https://twitter.com/lildude","name":"Twitter","silo_pub_token":"0987654321"},"1":{"uid":"https://example.com/foobar","name":"fooBar"}}}'
  t.test_files = FileList['test/*_test.rb']
  t.warning = false
end

RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = ['--enable-pending-cops']
end

desc 'run irb console'
task :console, :environment do |_, args|
  ENV['RACK_ENV'] = args[:environment] || 'development'
  exec 'pry -r ./app.rb -e "App = Sinatra::Application.new"'
end
