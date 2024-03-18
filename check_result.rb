require 'json'

paper_dir = ARGV[0].to_s
formats = ARGV[1].to_s.downcase.split(",")

# Check for generated files presence
if paper_dir.empty?
  raise "   !! ERROR: The paper dir can't be found"
else
  paper_pdf_path = paper_dir + "/paper.pdf"
  if File.exist?(paper_pdf_path)
    system("echo 'paper_pdf_path=#{paper_pdf_path}' >> $GITHUB_OUTPUT")
    system("echo 'Success! PDF file generated at: #{paper_pdf_path}'")
  else
    raise "   !! ERROR: Failed to generate PDF file" if formats.include?("pdf")
  end
end
