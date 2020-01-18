require 'asciidoctor-epub3'

RSpec.configure do |config|
  # configure rspec here
end

RSpec::Matchers.define :have_size do |expected|
  match {|actual| actual.size == expected }
  failure_message {|actual| %(expected #{actual} to have size #{expected}, but was #{actual.size}) }
end
