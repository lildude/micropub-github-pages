# frozen_string_literal: true

require 'rake/testtask'
require 'rubocop/rake_task'

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
