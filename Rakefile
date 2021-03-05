# frozen_string_literal: true

require 'rake/testtask'
require "standard/rake"
require 'yaml'
require 'json'

task default: 'test'

Rake::TestTask.new do |t|
  t.test_files = FileList['test/*_test.rb']
  t.warning = false
end

desc 'run irb console'
task :console, :environment do |_, args|
  ENV['RACK_ENV'] = args[:environment] || 'development'
  exec 'pry -r ./app.rb -e "App = Sinatra::Application.new"'
end

desc 'print config.yml as json'
task :jsoncfg do
  puts YAML.load_file('config.yml').to_json
end
