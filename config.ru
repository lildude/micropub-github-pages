require 'rubygems'
require 'bundler'

Bundler.require

require './micropub-github-pages'
run Sinatra::Application
