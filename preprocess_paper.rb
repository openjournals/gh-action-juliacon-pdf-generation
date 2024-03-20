require "theoj"
require "yaml"
require "securerandom"
require_relative "resources/crossref_xml_snippets"

action_path = ENV["ACTION_PATH"]
issue_id = ENV["ISSUE_ID"]
repo_url = ENV["REPO_URL"]
repo_branch = ENV["PAPER_BRANCH"]
acceptance = ENV["COMPILE_MODE"] == "accepted"

journal = Theoj::Journal.new(Theoj::JOURNALS_DATA[:jcon])
issue = Theoj::ReviewIssue.new(journal.data[:reviews_repository], issue_id)
issue.paper = Theoj::Paper.from_repo(repo_url, repo_branch)
submission = Theoj::Submission.new(journal, issue, issue.paper)

paper_path = issue.paper.paper_path

if paper_path.nil?
  system("echo 'CUSTOM_ERROR=Paper file not found.' >> $GITHUB_ENV")
  raise "   !! ERROR: Paper file not found"
else
  system("echo 'paper_file_path=#{paper_path}' >> $GITHUB_OUTPUT")
end

begin
  metadata = submission.article_metadata
rescue Theoj::Error => e
  system("echo 'CUSTOM_ERROR=#{e.message}.' >> $GITHUB_ENV")
  raise "   !! ERROR: Invalid submission metadata"
end

if acceptance && metadata[:published_at].to_s.strip.empty?
  metadata[:published_at] = Time.now.strftime("%Y-%m-%d")
end

metadata[:submitted_at] = "0000-00-00" if metadata[:submitted_at].to_s.strip.empty?
metadata[:published_at] = "0000-00-00" if metadata[:published_at].to_s.strip.empty?

metadata[:editor].transform_keys!(&:to_s)
metadata[:authors].each {|author| author.transform_keys!(&:to_s) }
metadata.transform_keys!(&:to_s)

paper_dir = File.dirname(paper_path)

metadata_file_path = paper_dir + "/paper-metadata.yaml"
File.open(metadata_file_path, "w") do |f|
  f.write metadata.to_yaml
end

for k in ["title", "authors", "affiliations", "keywords", "bibliography"]
  if issue.paper.paper_metadata[k].to_s == ""
    missing_metadata_key_msg = "Invalid submission metadata, #{k} not present in metadata"
    system("echo 'CUSTOM_ERROR=#{missing_metadata_key_msg}.' >> $GITHUB_ENV")
    raise "   !! ERROR: #{missing_metadata_key_msg}"
  end
end

system("echo '  ✅ Metadata generated at: #{metadata_file_path}'")

# ENV variables or default for issue/volume/year
journal_issue = ENV["JLCON_ISSUE"] || metadata["issue"]
volume = ENV["JLCON_VOLUME"] || metadata["volume"]
year = ENV["JLCON_YEAR"] || metadata["year"]
journal_name = Theoj::JOURNALS_DATA[:jcon][:name]

authors = issue.paper.paper_metadata["authors"]
affiliations = issue.paper.paper_metadata["affiliations"]

header_tex = <<~HEADERTEX
  % **************GENERATED FILE, DO NOT EDIT**************

  \\title{#{metadata["title"]}}

  #{ authors.map {|author| '\\author[' + author["affiliation"].to_s + ']{' + author["name"] + '}'}.join("\n") }
  #{ affiliations.map {|affiliation| '\\affil[' + affiliation["index"].to_s + ']{' + affiliation["name"] + '}' }.join("\n") }

  \\keywords{#{metadata["tags"].join(", ")}}

  \\hypersetup{
  pdftitle = {#{metadata["title"]}},
  pdfsubject = {JuliaCon #{year} Proceedings},
  pdfauthor = {#{authors.map { |author| author["name"] }.join(", ")}},
  pdfkeywords = {#{metadata["tags"].join(", ")}},
  }

HEADERTEX

header_file_path = paper_dir + "/header.tex"
File.open(header_file_path, 'w') do |f|
  f.write header_tex
end
system("echo '  ✅ File updated: #{header_file_path}'")

journal_dat_tex = <<~JOURNALDATTEX
  % **************GENERATED FILE, DO NOT EDIT**************

  \\def\\@journalName{#{journal_name}}
  \\def\\@volume{#{volume}}
  \\def\\@issue{#{journal_issue}}
  \\def\\@year{#{year}}
JOURNALDATTEX

journal_dat_file_path = paper_dir + "/journal_dat.tex"
File.open(journal_dat_file_path, 'w') do |f|
  f.write journal_dat_tex
end
system("echo '  ✅ File updated: #{journal_dat_file_path}'")

bib_tex = <<~BIBTEX
  % **************GENERATED FILE, DO NOT EDIT**************

  \\bibliographystyle{juliacon}
  \\bibliography{#{issue.paper.bibliography_path}}

BIBTEX

bib_file_path = paper_dir + "/bib.tex"
File.open(bib_file_path, 'w') do |f|
  f.write bib_tex
end
system("echo '  ✅ File updated: #{bib_file_path}'")

system("echo 'paper_dir=#{paper_dir}' >> $GITHUB_OUTPUT")

# crossref_args = <<-PANDOCARGS
# -V timestamp=#{Time.now.strftime('%Y%m%d%H%M%S')} \
# -V doi_batch_id=#{SecureRandom.hex} \
# -V formatted_doi=#{metadata['doi']} \
# -V archive_doi=#{metadata['archive_doi'] || "https://doi.org/10.5281/zenodo.10144853"} \
# -V review_issue_url=#{metadata['software_review_url']} \
# -V paper_url=https://proceedings.juliacon.org/papers/#{metadata['doi']} \
# -V paper_pdf_url=https://proceedings.juliacon.org/papers/#{metadata['doi']}.pdf \
# -V citations="" \
# -V authors="#{crossref_authors(issue.paper.authors)}" \
# -V month=#{Time.now.month} \
# -V day=#{Time.now.day} \
# -V year=#{year} \
# -V issue=#{journal_issue} \
# -V volume=#{volume} \
# -V page=#{metadata["page"]} \
# -V title="#{metadata['title']}" \
# -f markdown #{paper_dir + '/paper.tex'} -t opendocument -o #{paper_dir + '/paper.crossref.xml'} \
# --template #{paper_dir + '/crossref-template.xml'}
# PANDOCARGS

pandoc_defaults = {
  variables: {
    timestamp: Time.now.strftime('%Y%m%d%H%M%S'),
    doi_batch_id: SecureRandom.hex,
    formatted_doi: metadata['doi'],
    archive_doi: metadata['archive_doi'] || "Pending",
    review_issue_url: metadata['software_review_url'],
    paper_url: "https://proceedings.juliacon.org/papers/#{metadata['doi']}",
    paper_pdf_url: "https://proceedings.juliacon.org/papers/#{metadata['doi']}.pdf",
    citations: "",
    authors: "#{crossref_authors(issue.paper.authors)}",
    month: Time.now.month,
    day: Time.now.day,
    year: year,
    issue: journal_issue,
    volume: volume,
    page: metadata["page"],
    title: "#{metadata['title']}"
  },
  from: "markdown",
  to: "opendocument",
  'output-file': "#{paper_dir + '/paper.crossref.xml'}",
  template: "#{paper_dir + '/crossref-template.xml'}"
}

pandoc_defaults_file_path = paper_dir + "/pandoc_defaults.yaml"
File.open(pandoc_defaults_file_path, "w") do |f|
  f.write pandoc_defaults.to_yaml
end

crossref_args = "--defaults #{pandoc_defaults_file_path} #{paper_dir + '/paper.tex'}"

system("cp #{action_path}/resources/crossref-template.xml #{paper_dir}")

system("echo 'crossref_args=#{crossref_args}' >> $GITHUB_OUTPUT")
system("echo '  ✅ Crossref metadata ready'")
