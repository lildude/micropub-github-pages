# frozen_string_literal: true

env = ENV['RACK_ENV'].to_sym

require 'bundler/setup'
Bundler.require(:default, env)

require './app'
run Sinatra::Application
