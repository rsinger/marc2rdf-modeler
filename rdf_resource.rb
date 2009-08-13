require 'uri'
require 'builder'
require 'date'
require 'curies'
class RDFResource
  attr_reader :uri, :namespaces, :modifiers
  def initialize(uri)
    Curie.add_prefixes! :frbr=>"http://vocab.org/frbr/core#", :dct=>"http://purl.org/dc/terms/", :bibo=>"http://purl.org/ontology/bibo/",
      :skos=>"http://www.w3.org/2004/02/skos/core#", :rda=>"http://RDVocab.info/Elements/", :cat=>"http://schema.talis.com/2009/catalontology/",
       :rdfs=>"http://www.w3.org/2000/01/rdf-schema#", :ov=>"http://open.vocab.org/terms/", :event=>"http://purl.org/NET/c4dm/event.owl#"    
    @uri = Curie.parse uri
    @namespaces = ['http://www.w3.org/1999/02/22-rdf-syntax-ns#']

    @modifiers = {}
  end
  
  def assert(predicate, object, type=nil, lang=nil)
    uri = URI.parse(Curie.parse predicate)
    ns = nil
    elem = nil
    if uri.fragment
      ns, elem = uri.to_s.split('#')
      ns << '#'
    else
      elem = uri.path.split('/').last
      ns = uri.to_s.sub(/#{elem}$/, '')
    end
    attr_name = ''
    if i = @namespaces.index(ns)
      attr_name = "n#{i}_#{elem}"
    else
      @namespaces << ns
      attr_name = "n#{@namespaces.index(ns)}_#{elem}"
    end
    unless type
      val = object
    else
      @modifiers[object.object_id] ||={}
      @modifiers[object.object_id][:type] = type      
      val = case type
      when 'http://www.w3.org/2001/XMLSchema#dateTime' then DateTime.parse(object)
      when 'http://www.w3.org/2001/XMLSchema#date' then Date.parse(object)
      when 'http://www.w3.org/2001/XMLSchema#int' then object.to_i
      when 'http://www.w3.org/2001/XMLSchema#string' then object.to_s
      when 'http://www.w3.org/2001/XMLSchema#boolean'
        if object.downcase == 'true' || object == '1'
          true
        else
          false
        end
      else
        object
      end
    end
    if lang
      @modifiers[object.object_id] ||={}
      @modifiers[val.object_id][:language] = lang  
    end
    if self.instance_variable_defined?("@#{attr_name}")
      unless self.instance_variable_get("@#{attr_name}").is_a?(Array)
        att = self.instance_variable_get("@#{attr_name}")
        self.instance_variable_set("@#{attr_name}", [att])
      end
      self.instance_variable_get("@#{attr_name}") << val
    else
      self.instance_variable_set("@#{attr_name}", val)
    end
  end
  
  def relate(predicate, resource)
    self.assert(predicate, self.class.new(resource))
  end
  
  def to_rdfxml
    doc = Builder::XmlMarkup.new
    xmlns = {}
    i = 1
    @namespaces.each do | ns |
      next if ns == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'
      xmlns["xmlns:n#{i}"] = ns
      i += 1
    end
    doc.rdf :Description,xmlns.merge({:about=>uri}) do | rdf |
      self.instance_variables.each do | ivar |
        next unless ivar =~ /^@n[0-9]*_/
        prefix, tag = ivar.split('_',2)
        attrs = {}
        curr_attr = self.instance_variable_get("#{ivar}")
        prefix.sub!(/^@/,'')
        prefix = 'rdf' if prefix == 'n0'
        unless curr_attr.is_a?(Array)
          curr_attr = [curr_attr]
        end
        curr_attr.each do | val |
          if val.is_a?(RDFResource)
            attrs['rdf:resource'] = val.uri
          end
          if @modifiers[val.object_id]
            if @modifiers[val.object_id][:language]
              attrs['xml:lang'] = @modifiers[val.object_id][:language]
            end
            if @modifiers[val.object_id][:type]
              attrs['rdf:datatype'] = @modifiers[val.object_id][:type]
            end          
          end
          unless attrs['rdf:resource']
            rdf.tag!("#{prefix}:#{tag}", attrs, val)
          else
            rdf.tag!("#{prefix}:#{tag}", attrs)
          end
        end
      end
    end
    doc.target!
  end
  
end