# frozen_string_literal: true

require 'asciidoctor-epub3'

RSpec.configure do |config|
  config.before do
    FileUtils.rm_r temp_dir, force: true, secure: true
  end

  config.after do
    FileUtils.rm_r temp_dir, force: true, secure: true
  end

  def bin_script name, opts = {}
    path = Gem.bin_path (opts.fetch :gem, 'asciidoctor-epub3'), name
    [Gem.ruby, path]
  end

  def asciidoctor_bin
    bin_script 'asciidoctor', gem: 'asciidoctor'
  end

  def asciidoctor_epub3_bin
    bin_script 'asciidoctor-epub3'
  end

  def run_command cmd, *args
    Dir.chdir __dir__ do
      if Array === cmd
        args.unshift(*cmd)
        cmd = args.shift
      end
      env_override = { 'RUBYOPT' => nil }
      Open3.capture3 env_override, cmd, *args
    end
  end

  def temp_dir
    File.join __dir__, 'temp'
  end

  def temp_file path
    File.join temp_dir, path
  end

  def fixtures_dir
    File.join __dir__, 'fixtures'
  end

  def fixture_file path
    File.join fixtures_dir, path
  end

  def examples_dir
    File.join __dir__, '..', 'data', 'samples'
  end

  def example_file path
    File.join examples_dir, path
  end

  def darwin_platform?
    RbConfig::CONFIG['host_os'] =~ /darwin/
  end

  def skip_if_darwin
    # TODO: https://github.com/asciidoctor/asciidoctor-epub3/issues/236
    skip '#236: Kindlegen is unavailable for-bit MacOS' if darwin_platform?
  end
end

RSpec::Matchers.define :have_size do |expected|
  match {|actual| actual.size == expected }
  failure_message {|actual| %(expected #{actual} to have size #{expected}, but was #{actual.size}) }
end
