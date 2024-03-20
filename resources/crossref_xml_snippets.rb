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
        xml.person_name(:sequence => sequence, :contributor_role => "author") {
        xml.given_name given_name.encode(:xml => :text)
        if surname.nil?
          xml.surname "No Last Name".encode(:xml => :text)
        else
          xml.surname surname.encode(:xml => :text)
        end
        xml.ORCID "http://orcid.org/#{author.orcid}" if !orcid.nil?
        }
      end
    }
  end

  builder.doc.xpath('//contributors').to_xml
end
