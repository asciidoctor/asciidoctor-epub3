source 'https://rubygems.org'

# Look in asciidoctor-epub3.gemspec for runtime and development dependencies.
gemspec

group :optional do
  gem 'epubcheck', '3.0.1'
  if (ruby_version = Gem::Version.new RUBY_VERSION) < (Gem::Version.new '2.0.0')
    gem 'kindlegen', '2.9.4'
    gem 'pygments.rb', '0.6.3'
  else
    gem 'kindlegen', '3.0.3'
    gem 'pygments.rb', '1.1.2'
  end
end
