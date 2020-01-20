# frozen_string_literal: true

require_relative 'spec_helper'

describe 'asciidoctor-epub3' do
  it 'exits with 0 when prints version' do
    out, _, res = run_command asciidoctor_epub3_bin, '--version'
    expect(res.exitstatus).to eq(0)
    expect(out).to include %(Asciidoctor EPUB3 #{Asciidoctor::Epub3::VERSION} using Asciidoctor #{Asciidoctor::VERSION})
  end

  it 'exits with 1 when given nonexistent path' do
    _, err, res = run_command asciidoctor_epub3_bin, '/nonexistent'
    expect(res.exitstatus).to eq(1)
    expect(err).to match(/input file \/nonexistent( is)? missing/)
  end

  it 'converts sample book' do
    infile = example_file 'sample-book.adoc'
    outfile = temp_file 'sample-book.epub'

    _, _, res = run_command asciidoctor_epub3_bin, infile, '-o', outfile
    expect(res.exitstatus).to eq(0)
    expect(File).to exist(outfile)
  end
end
