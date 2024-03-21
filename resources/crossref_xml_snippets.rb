require "nokogiri"
require "bibtex"

def crossref_authors(authors)
  builder = Nokogiri::XML::Builder.new do |xml|
    xml.contributors {
      authors.each_with_index do |author, index|
        given_name = author.given_name
        surname = author.last_name
        orcid = author.orcid
        if index == 0
          sequence = "first"
        else
          sequence = "additional"
        end
        xml.person_name(sequence: sequence, contributor_role: "author") {
        xml.given_name given_name.encode(xml: :text)
        if surname.nil?
          xml.surname "No Last Name".encode(xml: :text)
        else
          xml.surname surname.encode(xml: :text)
        end
        xml.ORCID "http://orcid.org/#{author.orcid}" if !orcid.nil?
        }
      end
    }
  end

  builder.doc.xpath('//contributors').to_xml
end


# Generates the <citations></citations> XML block for Crossref
# Returns an XML fragment <citations></citations> with or
# without citations within
# TODO: should probably use Ruby builder templates here
def generate_citations(paper_path, bib_file_path)
  citations = File.read(paper_path).scan(/(?<=\\cite\{)\w+/).map {|c| c.prepend("@")}

  entries = BibTeX.open(bib_file_path, filter: :latex)
  ref_count = 1
  builder = Nokogiri::XML::Builder.new do |xml|
    xml.citation_list {
      entries.each do |entry|
      next if entry.comment?
      next if entry.preamble?

      if citations
        next unless citations.include?("@#{entry.key}")
      end

      xml.citation(key: "ref#{ref_count}") {
        if entry.has_field?('doi') && !entry.doi.empty?
          # Crossref DOIs need to be strings like 10.21105/joss.01461 rather
          # than https://doi.org/10.21105/joss.01461
          bare_doi = entry.doi.to_s[/\b(10[.][0-9]{4,}(?:[.][0-9]+)*\/(?:(?!["&\'<>])\S)+)\b/]

          # Check for shortDOI formatted DOIs http://shortdoi.org
          if bare_doi.nil?
            bare_doi = entry.doi.to_s[/\b(10\/[a-bA-z0-9]+)\b/]
          end

          # Escapes DOI in case there are weird characters in it
          xml.doi bare_doi.encode(xml: :text)
        else
          xml.unstructured_citation entry.values.map {|v| v.to_s.encode(xml: :text)}.join(", ")
        end
      }
      ref_count += 1
    end
    }
  end
  builder.doc.xpath('//citation_list').to_xml
end

