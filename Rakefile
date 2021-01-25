# frozen_string_literal: true

require 'rake/testtask'
require 'rubocop/rake_task'
require 'yaml'
require 'json'

task default: 'test'

Rake::TestTask.new do |t|
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

desc 'print config.yml as json'
task :jsoncfg do
  puts YAML.load_file('config.yml').to_json
end
