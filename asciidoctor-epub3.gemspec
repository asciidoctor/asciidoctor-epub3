# -*- encoding: utf-8 -*-
require File.expand_path('lib/asciidoctor-epub3/version', File.dirname(__FILE__))

Gem::Specification.new do |s| 
  s.name = 'asciidoctor-epub3'
  s.version = Asciidoctor::Epub3::VERSION

  s.summary = 'Converts AsciiDoc documents to EPUB3 and KF8/MOBI (Kindle) e-book formats'
  s.description = <<-EOS
An extension for Asciidoctor that converts AsciiDoc documents to EPUB3 and KF8/MOBI (Kindle) e-book archives.
  EOS

  s.authors = ['Dan Allen', 'Sarah White']
  s.email = 'dan@opendevise.io'
  s.homepage = 'https://github.com/asciidoctor/asciidoctor-epub3'
  s.license = 'MIT'

  s.required_ruby_version = '>= 1.9'

  begin
    s.files = `git ls-files -z -- */* {README.adoc,LICENSE.adoc,NOTICE.adoc,Rakefile}`.split "\0"
  rescue
    s.files = Dir['**/*']
  end

  s.executables = %w(asciidoctor-epub3 adb-push-ebook)
  s.test_files = s.files.grep(/^(?:test|spec|feature)\/.*$/)
  s.require_paths = %w(lib)

  s.has_rdoc = true
  s.rdoc_options = %(--charset=UTF-8 --title="Asciidoctor EPUB3" --main=README.adoc -ri)
  s.extra_rdoc_files = %w(README.adoc LICENSE.adoc NOTICE.adoc)

  s.add_development_dependency 'rake', '~> 10.0'
  #s.add_development_dependency 'rdoc', '~> 4.1.0'

  s.add_runtime_dependency 'asciidoctor', ['>= 1.5.0.rc.2', '< 1.6.0']
  s.add_runtime_dependency 'gepub', '~> 0.6.9.2'
  s.add_runtime_dependency 'thread_safe', '~> 0.3.4'

  # optional
  #s.add_runtime_dependency 'kindlegen', '~> 2.9.0'
  #s.add_runtime_dependency 'epubcheck', '~> 3.0.1'
  #s.add_runtime_dependency 'pygments.rb', '0.5.4'
end
