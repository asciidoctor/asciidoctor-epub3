module Asciidoctor
module Epub3
class SpineItemProcessor < Extensions::IncludeProcessor
  def initialize document
    @document = document
  end

  # NOTE only fires for includes in spine document if registered directly on the instance of the spine document
  def process doc, reader, target, attributes
    spine_doc = doc
    # TODO allow URI value
    unless ::File.file?(include_file = (spine_doc.normalize_system_path target, reader.dir, nil, target_name: 'include file'))
      warn %(asciidoctor: WARNING: #{reader.line_info}: include file not found: #{include_file})
      return
    end
    inherited_attrs = spine_doc.attributes.dup
    # QUESTION should we keep backend-epub3 for convenience?
    %w(backend-epub3 backend-epub3-doctype-book docdir docfile docname doctitle outfilesuffix spine).each {|key| inherited_attrs.delete key }
    if (leveloffset = inherited_attrs['leveloffset'])
      leveloffset = inherited_attrs['leveloffset'] = %(#{leveloffset}@) unless leveloffset.end_with? '@'
    end

    # parse header to get author information
    spine_item_doc_meta = ::Asciidoctor.load_file include_file,
        safe: spine_doc.safe,
        backend: 'epub3-xhtml5',
        doctype: :article,
        parse_header_only: true,
        attributes: leveloffset ? { 'leveloffset' => leveloffset } : nil

    # blank out author information if present in sub-document
    # FIXME this is a huge hack...we need a cleaner way to do this; perhaps an API method that retrieves all the author attribute names
    if spine_item_doc_meta.attr? 'author'
      %w(author firstname lastname email authorinitials authors authorcount).each {|key| inherited_attrs.delete key }
      idx = 1
      while inherited_attrs.key? %(author_#{idx})
        %W(author_#{idx} firstname_#{idx} lastname_#{idx} email_#{idx} authorinitials_#{idx}).each {|key| inherited_attrs.delete key }
        idx += 1
      end
    end

    # REVIEW reaching into converter to resolve document id feels like a hack; should happen in Asciidoctor parser
    # also, strange that "id" doesn't work here
    idprefix = (spine_doc.attr 'idprefix') || (spine_item_doc_meta.attr 'idprefix')
    idseparator = (spine_doc.attr 'idseparator') || (spine_item_doc_meta.attr 'idseparator')
    inherited_attrs['css-signature'] = DocumentIdGenerator.generate_id spine_item_doc_meta, idprefix, idseparator
    inherited_attrs['docreldir'] = ::File.dirname target

    # NOTE can't assign spine document as parent since there's too many assumptions in the Asciidoctor processor
    spine_item_doc = ::Asciidoctor.load_file include_file,
        # setting base_dir breaks if outdir is not a subdirectory of spine_doc.base_dir
        #base_dir: spine_doc.base_dir,
        # NOTE won't write to correct directory if safe mode is :secure
        safe: spine_doc.safe,
        backend: 'epub3-xhtml5',
        doctype: :article,
        header_footer: true,
        catalog_assets: true,
        attributes: inherited_attrs

    # restore attributes to those defined in the document header
    spine_item_doc.restore_attributes

    # FIXME core should register document ID if specified
    unless (refs = spine_item_doc.references)[:ids].include? spine_item_doc.id
      spine_item_doc.register :ids, [spine_item_doc.id, (spine_item_doc.attr 'docreftext') || spine_item_doc.doctitle]
    end

    refs[:spine] = spine_doc
    refs[:spine_items] = ((spine_doc.references[:spine_items] ||= []) << spine_item_doc)
    # NOTE if there are attribute assignments between the include directives,
    # then this ordered list is not continguous, so bailing on the idea
    #reader.replace_line %(. link:#{::File.basename(spine_item_doc.attr 'outfile')}[#{spine_item_doc.doctitle}])
    nil
  end

  # handles? should get the attributes on include directive as the second argument
  def handles? target
    (@document.attr? 'spine') && (ASCIIDOC_EXTENSIONS.include? ::File.extname(target))
  end

  # FIXME this method shouldn't be required
  def update_config config
    (@config ||= {}).update config
  end
end
end
end
