$KCODE = 'u'
require 'rubygems'
#require 'marc'
require 'jcode'
require 'enhanced_marc'
require 'rdf_resource'
require 'lcsh_labels'
require 'isbn/tools'
reader = MARC::ForgivingReader.new('cca.utf8.mrc')

i = 0

class String
  def slug
    slug = self.gsub(/[^\w\s\-]/,"")
    slug.gsub!(/\s/,"_")
    slug.downcase
  end  
  def strip_trailing_punct
    self.sub(/[\.:,;\/\s]\s*$/,'').strip
  end
  def strip_leading_and_trailing_punct
    str = self.sub(/[\.:,;\/\s\)\]]\s*$/,'').strip
    str.sub!(/^\s*[\.:,;\/\s\(\[]/,'').strip
    str
  end  
  def lpad(count=1)
    "#{" " * count}#{self}"
  end
end

class MARC::Record
  @@base_uri = 'http://library.cca.edu/core'
  @@missing_id_prefix = 'cca'
  @@missing_id_counter = 0
    
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
    literal.strip_trailing_punct  
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
    id = self['001'].value.strip
    resources << manifestation = RDFResource.new("#{@@base_uri}/m/#{id}")    
    manifestation.relate("[rdf:type]", "[frbr:Manifestation]")
    if self['245']
      if self['245']['a']
        title = self['245']['a'].strip_trailing_punct
        manifestation.assert("[rda:titleProper]", self['245']['a'].strip_trailing_punct)
      else
        puts "No 245$a:  #{self['245']}"
      end
      if self['245']['b']
        title << " "+self['245']['b'].strip_trailing_punct
        manifestation.assert("[rda:otherTitleInformation]", self['245']['b'].strip_trailing_punct)
      end
      if self['245']['c']
        manifestation.assert("[rda:statementOfResponsibility]", self['245']['c'].strip_trailing_punct)
      end
    end
    manifestation.assert("[dct:title]", title)
    if self['210']
      manifestation.assert("[bibo:shortTitle]", self['210']['a'].strip_trailing_punct)
    end
    if self['020'] && self['020']['a']
      isbn = ISBN_Tools.cleanup(self['020']['a'].strip_trailing_punct)
      if ISBN_Tools.is_valid?(isbn)
        #manifestation.assert("[bibo:isbn]", isbn)
        if isbn.length == 10
          manifestation.assert("[bibo:isbn10]",isbn)
          manifestation.assert("[bibo:isbn13]", ISBN_Tools.isbn10_to_isbn13(isbn))
        else
          manifestation.assert("[bibo:isbn13]",isbn)
          manifestation.assert("[bibo:isbn10]", ISBN_Tools.isbn13_to_isbn10(isbn))          
        end
      end
    end
    
    if self['022'] && self['022']['a']
      manifestation.assert("[bibo:issn]", self['022']['a'].strip_trailing_punct)
    end    
    if self['250'] && self['250']['a']
      manifestation.assert("[bibo:edition]", self['250']['a'])
    end
    if self['246'] && self['246']['a']
      manifestation.assert("[rda:parallelTitleProper]", self['246']['a'].strip_trailing_punct)
    end
    if self['767'] && self['767']['t']
      manifestation.assert("[rda:parallelTitleProper]", self['767']['t'].strip_trailing_punct)
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
        
        if subject.tag =~ /^(600|610|696|697)$/
          if !subdivided?(subject)
            concept = RDFResource.new("#{@@base_uri}/i/#{literal.slug}#concept")
            identity = RDFResource.new("#{@@base_uri}/i/#{literal.slug}")
          else
            concept = RDFResource.new("#{@@base_uri}/s/#{literal.slug}#concept")
            identity_subject = top_concept(subject)
            identity = RDFResource.new("#{@@base_uri}/i/#{subject_to_string(identity_subject).slug}")
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
            concept = RDFResource.new("#{@@base_uri}/e/#{literal.slug}#concept")
            event = RDFResource.new("#{@@base_uri}/e/#{literal.slug}")
          else
            concept = RDFResource.new("#{@@base_uri}/s/#{literal.slug}#concept")
            event_subject = top_concept(subject)
            event = RDFResource.new("#{@@base_uri}/e/#{subject_to_string(event_subject).slug}")
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
            concept = RDFResource.new("#{@@base_uri}/w/#{literal.slug}#concept")
            work = RDFResource.new("#{@@base_uri}/w/#{literal.slug}")
          else
            concept = RDFResource.new("#{@@base_uri}/s/#{literal.slug}#concept")
            work_subject = top_concept(subject)
            work = RDFResource.new("#{@@base_uri}/w/#{subject_to_string(work_subject).slug}")
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
          concept = RDFResource.new("#{@@base_uri}/s/#{literal.slug}#concept")  
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
      manifestation.assert("[bibo:lccn]", self['010']['a'].strip)
    end
    oclcnums = self.find_all {|field| field.tag == "035" && (field['a'] =~ /^\(OCoLC\)/ || field['b'] == "OCoLC")}
    oclcnums.each do | oclcnum |
      manifestation.assert("[bibo:oclcnum]",oclcnum['a'].sub(/^\(OCoLC\)/,''))
    end
    pages = self.find_all {|field| field.tag == "300" && (field['a'] =~ /\sp\./)}
    pages.each do | page |
      manifestation.assert("[bibo:pages]",page['a'].strip_trailing_punct)
    end
    if self.form      
      manifestation.assert("[dc:format]", self.form(true))
    end
    if self['100']
      identity = Identity.new_from_field(self['100'], "#{@@base_uri}/i/")     
    end

    persons = self.find_all{|field| field.tag =~ /700|100|800|600|896|790|690/ && (field['e'] || field['4'])}
    persons.each do | person |
      if person['e']
        puts "$e: #{person['e']}"
      end
      if person['4']
        puts "$4: #{person['4']}"
      end      
    end      
    resources
  end
end

class MARC::BookRecord

  def to_rdf_resources
    resources = super
    book = resources[0]
    if self.is_conference?
      book.relate("[rdf:type]","[bibo:Proceedings]")
    else
      book.relate("[rdf:type]", "[bibo:Book]")
    end
    if self.nature_of_contents
      self.nature_of_contents(true).each do | genre |        
        book.assert("[dct:type]", genre)
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

class Identity
  def self.new_from_field(field, base_uri)
    name = ''
    if field.tag == '100'
      name << field['a'].strip_trailing_punct
      ['b','c','d','q'].each do | code |
        name << field[code].lpad.strip_trailing_punct if field[code]
      end
    elsif field.tag == '110'
      name << field['a'].strip_trailing_punct
      ['b','c','d'].each do | code |
        name << field[code].lpad.strip_trailing_punct if field[code]
      end
    end      
    resource = RDFResource.new("#{base_uri}#{name.slug}")
    if field.tag == '100'
      resource.relate("[rdf:type]", "[foaf:Person]")
      if field.indicator1 == "2"
        last,first = field['a'].strip_trailing_punct.split(", ")
        if last && first
          resource.assert("[foaf:surname]", last)
          resource.assert("[foaf:givenname]", first.strip)
        end
      end
      if field['q']
        resource.assert("[dct:alternate]", field['q'].strip_leading_and_trailing_punct)
      end
    elsif field.tag == '110'
      resource.relate("[rdf:type]", "[foaf:Organization]")
    end
    resource.assert("[foaf:name]", field['a'].strip_trailing_punct)
    if field['d']
      resource.assert("[dct:date]", field['d'])
    end
    resource
  end
  
  def self.relations(field)
    
  end
end
  
begin
  yaml = YAML.load_file('relation.yml')
rescue Errno::ENOENT
  relations = {}
  reader.each do | record |
    relators = record.find_all{|field| field.tag =~ /100|110|111|270|400|410|411|600|610|611|696|697|698|700|710|711|720|790|791|792|796|797|798|800|810|811|896|897|898/ && (field['e'] || field['4'])}
    relators.each do | relator |
      relator.subfields.each do | subfield |
        if subfield.code == 'e' && !["111","270","411","611","698","711","792","798","811","898"].index(relator.tag)
          relations[subfield.value.strip_trailing_punct] = nil
        end

        if subfield.code == "4"
          relations[subfield.value.strip_trailing_punct] = nil
        end
      end      
    end
  end
  fh = open('relation.yml', "w+")
  fh << relations.to_yaml
  fh.close
  exit
end
@resources = []
reader.each do | record |
  @resources += record.to_rdf_resources
  i += 1
  #break if i > 1000
end
@resources.each do | resource |
  #puts resource.to_rdfxml
end