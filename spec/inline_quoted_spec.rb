# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Asciidoctor::Epub3::Converter - Inline Quoted' do
  subject { Asciidoctor::Epub3::Converter.new('epub3').convert_inline_quoted node }

  let(:parent) { instance_double('parent').as_null_object }
  let(:node) { Asciidoctor::Inline.new parent, :bar, 'text', type: type }

  it 'resolves inline quotes' do
    book, = to_epub fixture_file('inline-quote/book.adoc')
    chapter = book.item_by_href 'chapter.xhtml'
    expect(chapter).not_to be_nil
    expect(chapter.content).to include '<p><span class="inline-quote">Knowledge kills action; action requires the veils of illusion.</span></p>'
    expect(chapter.content).to include '<p><strong>enclosed in asterisk characters</strong></p>'
    expect(chapter.content).to include '<p>enclosed in plus characters</p>'
    expect(chapter.content).to include "<p>`single grave accent to the left and a single acute accent to the right'</p>"
    expect(chapter.content).to include "<p>``two grave accents to the left and two acute accents to the right''</p>"
    expect(chapter.content).to include '<p><mark>hashes around text</mark></p>'
  end

  context 'double' do
    let(:type) { :double }

    it 'wraps with double quotes' do
      expect(subject).to eq(%(“text”))
    end
  end

  context 'single' do
    let(:type) { :single }

    it 'wraps with single quotes' do
      expect(subject).to eq(%(‘text’))
    end
  end

  context 'strong' do
    let(:type) { :strong }

    it 'renders as strong element' do
      expect(subject).to eq('<strong>text</strong>')
    end
  end

  context 'monospaced' do
    let(:type) { :monospaced }

    it 'renders as code element' do
      expect(subject).to eq('<code class="literal">text</code>')
    end
  end

  context 'latexmath' do
    let(:type) { :latexmath }

    it 'renders as code element' do
      expect(subject).to eq('<code class="literal">text</code>')
    end
  end

  context 'with role' do
    let :node do
      Asciidoctor::Inline.new parent, :bar, 'text', type: type, attributes: { 'role' => 'foo' }
    end

    context 'emphasis' do
      let(:type) { :emphasis }

      it 'puts role as class' do
        expect(subject).to eq('<em class="foo">text</em>')
      end
    end

    context 'double' do
      let(:type) { :double }

      it 'wraps with span element and puts role as class' do
        expect(subject).to eq('<span class="foo">“text”</span>')
      end
    end

    context 'custom type' do
      let(:type) { :custom_type }

      it 'wraps with span element and puts role as class' do
        expect(subject).to eq('<span class="foo">text</span>')
      end
    end
  end

  context 'with id' do
    let(:node) { Asciidoctor::Inline.new parent, :bar, 'text', type: type, id: 'ID' }

    context 'emphasis' do
      let(:type) { :emphasis }

      it 'puts role as class' do
        expect(subject).to eq('<em id="ID">text</em>')
      end
    end

    context 'double' do
      let(:type) { :double }

      it 'wraps with span element and puts role as class' do
        expect(subject).to eq('<span id="ID">“text”</span>')
      end
    end

    context 'custom type' do
      let(:type) { :custom_type }

      it 'wraps with span element and puts role as class' do
        expect(subject).to eq('<span id="ID">text</span>')
      end
    end
  end

  context 'with id and role' do
    let :node do
      Asciidoctor::Inline.new parent, :bar, 'text', type: type, id: 'ID', attributes: { 'role' => 'foo' }
    end

    context 'emphasis' do
      let(:type) { :emphasis }

      it 'puts role as class' do
        expect(subject).to eq('<em id="ID" class="foo">text</em>')
      end
    end

    context 'double' do
      let(:type) { :double }

      it 'wraps with span element and puts role as class' do
        expect(subject).to eq('<span id="ID" class="foo">“text”</span>')
      end
    end

    context 'custom type' do
      let(:type) { :custom_type }

      it 'wraps with span element and puts role as class' do
        expect(subject).to eq('<span id="ID" class="foo">text</span>')
      end
    end
  end
end
