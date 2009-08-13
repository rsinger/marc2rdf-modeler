$KCODE = 'u'
require 'rubygems'
#require 'marc'
require 'jcode'
require 'enhanced_marc'
require 'rdf_resource'
require 'lcsh_labels'
reader = MARC::Reader.new('cca.utf8.mrc')

i = 0

class MARC::Record
  @@base_uri = 'http://library.cca.edu/core'
  @@missing_id_prefix = 'cca'
  @@missing_id_counter = 0
  
  def strip_trailing_punct(str)
    return str.sub(/[\.:,;\/\s]\s*$/,'').strip
  end
  
  def slug_literal(str)
    slug = str.gsub(/[^\w\s\-]/,"")
    slug.gsub!(/\s/,"_")
    slug.downcase
  end
  
  def subdivided?(subject)
    subject.subfields.each do | subfield |
      if ["k","v","x","y","z"]
        return true
      end
    end
    return false
  end
  
  def subject_to_string(subject)
    literal = ''
    subject.subfields.each do | subfield |
      if !literal.empty?
        if ["v","x","y","z"].index(subfield.code)
          literal << '--'
        else
          literal << ' ' if subfield.value =~ /^[\w\d]/
        end
      end
      literal << subfield.value
    end
    literal.sub(/\.\s*/,'')    
  end
  
  def top_concept(subject)
    field = MARC::DataField.new(subject.tag, subject.indicator1, subject.indicator2)
    subject.subfields.each do | subfield |
      unless ["k","v","x","y","z"].index(subfield.code)
        sub = MARC::Subfield.new(subfield.code, subfield.value)
        field.append(sub)
      end
    end
    return field
  end
  
  def to_rdf_resources
    resources = []
    unless self['001']
      controlnum = MARC::ControlField.new('001')
      controlnum.value = "#{@@missing_id_prefix}#{@@missing_id_counter}"
      @@missing_id_counter += 1
      self << controlnum
    end
    id = self['001'].value
    resources << manifestation = RDFResource.new("#{@@base_uri}/m/#{id}")    
    manifestation.relate("[rdf:type]", "[frbr:Manifestation]")
    if self['245']
      if self['245']['a']
        title = strip_trailing_punct(self['245']['a'])
        manifestation.assert("[rda:titleProper]", strip_trailing_punct(self['245']['a']))
      else
        puts "No 245$a:  #{self['245']}"
      end
      if self['245']['b']
        title << " "+strip_trailing_punct(self['245']['b'])
        manifestation.assert("[rda:otherTitleInformation]", strip_trailing_punct(self['245']['b']))
      end
      if self['245']['c']
        manifestation.assert("[rda:statementOfResponsibility]", strip_trailing_punct(self['245']['c']))
      end
    end
    manifestation.assert("[dct:title]", title)
    if self['210']
      manifestation.assert("[bibo:shortTitle]", strip_trailing_punct(self['210']['a']))
    end
    if self['020'] && self['020']['a']
      manifestation.assert("[bibo:isbn]", strip_trailing_punct(self['020']['a']))
    end
    
    if self['022'] && self['022']['a']
      manifestation.assert("[bibo:issn]", strip_trailing_punct(self['022']['a']))
    end    
    if self['250'] && self['250']['a']
      manifestation.assert("[bibo:edition]", self['250']['a'])
    end
    if self['246'] && self['246']['a']
      manifestation.assert("[rda:parallelTitleProper]", strip_trailing_punct(self['246']['a']))
    end
    if self['767'] && self['767']['t']
      manifestation.assert("[rda:parallelTitleProper]", strip_trailing_punct(self['767']['t']))
    end    
    subjects = self.find_all {|field| field.tag =~ /^6../}
    
    subjects.each do | subject |
      authority = false
      authorities = []
      literal = subject_to_string(subject)
      manifestation.assert("[dc:subject]", literal)
      if !["653","690","691","696","697", "698", "699"].index(subject.tag) && subject.indicator2 =~ /^(0|1)$/        
        Label.all(:label=>literal).each do | auth |    
          next if (subject.indicator2 == "0" && auth.uri =~ /http:\/\/lcsubjects\.org\/subjects\/sj/) || 
            (subject.indicator2 == "1" && auth.uri =~ /http:\/\/lcsubjects\.org\/subjects\/sh/)
          manifestation.relate("[dct:subject]", auth.uri)
          authorities << auth.uri
          authority = true
        end
      end
      if ["600","610","611","630"].index(subject.tag) || !authority

        slugged_id = slug_literal(literal)
        
        if subject.tag =~ /^(600|610|696|697)$/
          if !subdivided?(subject)
            concept = RDFResource.new("#{@@base_uri}/i/#{slugged_id}#concept")
            identity = RDFResource.new("#{@@base_uri}/i/#{slugged_id}")
          else
            concept = RDFResource.new("#{@@base_uri}/s/#{slugged_id}#concept")
            identity_subject = top_concept(subject)
            identity = RDFResource.new("#{@@base_uri}/i/#{slug_literal(subject_to_string(identity_subject))}")
          end
          if subject.tag =~ /^(600|696)$/
            identity.relate("[rdf:type]","[foaf:Person]")
            if subject['u']
              identity.assert("[ov:affiliation]", subject['u'].sub)
            end
            concept.relate("[skos:inScheme]", "#{@@base_uri}/s#personalNames")
          else
            identity.relate("[rdf:type]","[foaf:Organization]")
            identity.assert("[dct:description]", subject['u'])
            concept.relate("[skos:inScheme]", "#{@@base_uri}/s#corporateNames")            
          end
          concept.relate("[rdfs:seeAlso]", identity.uri)
          identity.relate("[rdfs:seeAlso]", concept.uri)
          name = subject['a']
          if subject['b']
            name << " #{subject['b']}"
          end
          identity.assert("[foaf:name]",name)
          if subject['d']
            identity.assert("[dct:date]", subject['d'])
          end      
          resources << identity      
        elsif subject.tag =~ /^(611|698)$/
          if !subdivided?(subject)
            concept = RDFResource.new("#{@@base_uri}/e/#{slugged_id}#concept")
            event = RDFResource.new("#{@@base_uri}/e/#{slugged_id}")
          else
            concept = RDFResource.new("#{@@base_uri}/s/#{slugged_id}#concept")
            event_subject = top_concept(subject)
            event = RDFResource.new("#{@@base_uri}/e/#{slug_literal(subject_to_string(identity_subject))}")
          end   
          concept.relate("[skos:inScheme]", "#{@@base_uri}/s#meetings")          
          event.relate("[rdf:type]","[event:Event]")
          concept.relate("[rdfs:seeAlso]", event.uri)
          event.relate("[rdfs:seeAlso]", concept.uri)          
          event.assert("[dct:title]", subject['a'])
          if subject['d']
            event.assert("[dct:date]", subject['d'])
          end
          if subject['c']
            event.assert("[dct:description]", subject['c'])
          end
          resources << event          
        elsif subject.tag =~ /^(630|699)$/
          unless subdivided?(subject)
            concept = RDFResource.new("#{@@base_uri}/w/#{slugged_id}#concept")
            work = RDFResource.new("#{@@base_uri}/w/#{slugged_id}")
          else
            concept = RDFResource.new("#{@@base_uri}/s/#{slugged_id}#concept")
            work_subject = top_concept(subject)
            work = RDFResource.new("#{@@base_uri}/w/#{slug_literal(subject_to_string(identity_subject))}")
          end
          concept.relate("[skos:inScheme]", "#{@@base_uri}/s#uniformTitles")          
          work.relate("[rdf:type]","[frbr:Work]")
          concept.relate("[rdfs:seeAlso]", work.uri)
          work.relate("[rdfs:seeAlso]", concept.uri)          
          work.assert("[dct:title]", subject['a'])
          if subject['d']
            work.assert("[dct:date]", subject['d'])
          end
          if subject['f']
            work.assert("[dct:date]", subject['f'])
          end     
          resources << work     
        else
          concept = RDFResource.new("#{@@base_uri}/s/#{slugged_id}#concept")  
          if subject.tag =~ /^(650|690)$/
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#topicalTerms")
          elsif subject.tag =~ /^(651|691)$/
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#geographicNames")
          elsif subject.tag = "655"
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#genreFormTerms")
          elsif subject.tag = "648"
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#chronologicalTerms")
          elsif subject.tag = "656"
            concept.relate("[skos:inScheme]","#{@@base_uri}/s#occupations")
          end
        end
        concept.assert("[skos:prefLabel]", literal)
        
        authorities.each do | auth |
          concept.relate("[skos:exactMatch]", auth)
        end
        
        subject.subfields.each do | subfield |
          scheme = case subfield.code
          when "v" then "#{@@base_uri}/s#formSubdivision"
          when "x" then "#{@@base_uri}/s#generalSubdivision"
          when "y" then "#{@@base_uri}/s#chronologicalSubdivision"
          when "z" then "#{@@base_uri}/s#geographicSubdivision"
          else nil
          end
          if scheme
            concept.relate("[skos:inScheme]",scheme)
          end
        end
        resources << concept
      end
      authority = false
    end
    if self['010'] && self['010']['a']
      manifestation.assert("[bibo:lccn]", self['010']['a'])
    end
    resources
  end
end

class MARC::BookRecord

  def to_rdf_resources
    resources = super
    book = resources[0]
    book.relate("[rdf:type]", "[bibo:Book]")
    if self.nature_of_contents
      self.nature_of_contents(true).each do | genre |        
        book.assert("[cat:genre]", genre)
      end
    end
    #puts book.to_rdfxml
    return resources
  end
end

class MARC::DataField
  def [](code)
    subfield = self.find {|s| s.code == code}
    return subfield.value.sub(/\.\s*/,'') if subfield
    return
  end
end


@resources = []
reader.each do | record |
  @resources += record.to_rdf_resources
  i += 1
  break if i > 100
end
@resources.each do | resource |
  puts resource.to_rdfxml
end