# frozen_string_literal: true

require_relative 'spec_helper'

describe 'asciidoctor-epub3' do
  it 'exits with 0 when prints version' do
    system 'bundle', 'exec', 'asciidoctor-epub3', '--version', out: File::NULL, err: File::NULL
    expect($?.exitstatus).to eq(0)
  end

  it 'exits with 1 when given nonexistent path' do
    system 'bundle', 'exec', 'asciidoctor-epub3', '/nonexistent', out: File::NULL, err: File::NULL
    expect($?.exitstatus).to eq(1)
  end

  it 'successfully converts sample book' do
    sampledir = File.join __dir__, '../data/samples/'
    infile = File.join sampledir, 'sample-book.adoc'
    outfile = File.join sampledir, 'sample-book.epub'

    File.delete outfile if File.exist? outfile
    system 'bundle', 'exec', 'asciidoctor-epub3', infile, '-o', outfile, out: File::NULL, err: File::NULL
    expect($?.exitstatus).to eq(0)
    expect(File).to exist(outfile)
  end
end
