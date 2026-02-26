# frozen_string_literal: true

require 'asciidoctor-epub3'

Zip.force_entry_names_encoding = 'UTF-8'

RSpec.configure do |config|
  config.before do
    FileUtils.rm_r temp_dir, force: true, secure: true
  end

  config.after do
    FileUtils.rm_r temp_dir, force: true, secure: true
  end

  def bin_script(name, opts = {})
    path = Gem.bin_path (opts.fetch :gem, 'asciidoctor-epub3'), name
    [Gem.ruby, path]
  end

  def asciidoctor_bin
    bin_script 'asciidoctor', gem: 'asciidoctor'
  end

  def asciidoctor_epub3_bin
    bin_script 'asciidoctor-epub3'
  end

  def run_command(cmd, *args)
    Dir.chdir __dir__ do
      if cmd.is_a?(Array)
        args.unshift(*cmd)
        cmd = args.shift
      end
      env_override = { 'RUBYOPT' => nil }
      Open3.capture3 env_override, cmd, *args
    end
  end

  def temp_dir
    Pathname.new(__dir__).join 'temp'
  end

  def temp_file(*path)
    temp_dir.join(*path)
  end

  def fixtures_dir
    Pathname.new(__dir__).join 'fixtures'
  end

  def fixture_file(*path)
    fixtures_dir.join(*path)
  end

  def examples_dir
    Pathname.new(__dir__).join '..', 'samples'
  end

  def example_file(*path)
    examples_dir.join(*path)
  end

  def convert(input, opts = {})
    opts[:backend] = 'epub3'
    opts[:header_footer] = true
    opts[:mkdirs] = true
    opts[:safe] = Asciidoctor::SafeMode::UNSAFE unless opts.key? :safe

    if input.is_a?(Pathname)
      opts[:to_dir] = temp_dir.to_s unless opts.key?(:to_dir) || opts.key?(:to_file)
      Asciidoctor.convert_file input.to_s, opts
    else
      Asciidoctor.convert input, opts
    end
  end

  def to_epub(input, opts = {})
    result = convert input, opts
    return result if result.is_a?(GEPUB::Book)

    output = Pathname.new result.attr('outfile')
    [
      output.open do |f|
        GEPUB::Book.parse f
      end,
      output
    ]
  end
end

RSpec::Matchers.define :have_size do |expected|
  match { |actual| actual.size == expected }
  failure_message { |actual| %(expected #{actual} to have size #{expected}, but was #{actual.size}) }
end

RSpec::Matchers.define :have_item_with_href do |expected|
  match { |actual| actual.item_by_href expected }
  failure_message { |actual| %(expected '#{actual.title}' to have item with href #{expected}) }
end
