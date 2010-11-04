#!/usr/bin/env ruby -wKU

# Small script to start the ENSIME client server
# 
# You have to send the path to the support folder as the 
# first argument

puts "======================"
puts "Starting client server"
puts "======================"

require ARGV[0] + "/server.rb"
require ARGV[2] + '/lib/osx/plist'

Ensime::Server.new(ARGV[1],ARGV[0]).start()