# ~*~ encoding: utf-8 ~*~
require File.expand_path(File.join(File.dirname(__FILE__), "helper"))

context "Wiki" do
  setup do
    @wiki                       = Gollum::Wiki.new(testpath("examples/lotr.git"))
    Gollum::Wiki.markup_classes = nil
  end

  test "#markup_class gets default markup" do
    assert_equal Gollum::Markup, Gollum::Wiki.markup_class
  end

  test "#default_markup_class= doesn't clobber alternate markups" do
    custom    = Class.new(Gollum::Markup)
    custom_md = Class.new(Gollum::Markup)

    Gollum::Wiki.markup_classes            = Hash.new Gollum::Markup
    Gollum::Wiki.markup_classes[:markdown] = custom_md
    Gollum::Wiki.default_markup_class      = custom

    assert_equal custom, Gollum::Wiki.default_markup_class
    assert_equal custom, Gollum::Wiki.markup_classes[:orgmode]
    assert_equal custom_md, Gollum::Wiki.markup_classes[:markdown]
  end

  test "repo path" do
    assert_equal testpath("examples/lotr.git"), @wiki.path
  end

  test "git repo" do
    assert_equal Gollum::Git::Repo, @wiki.repo.class
    assert @wiki.exist?
  end

  test "shows paginated log with no page" do
    Gollum::Wiki.per_page = 3
    commits               = @wiki.repo.commits[0..2].map(&:id)
    assert_equal commits, @wiki.log.map { |c| c.id }
  end

  test "shows paginated log with 1st page" do
    Gollum::Wiki.per_page = 3
    commits               = @wiki.repo.commits[0..2].map(&:id)
    assert_equal commits, @wiki.log(:page => 1).map(&:id)
  end

  test "shows paginated log with next page" do
    Gollum::Wiki.per_page = 3
    commits               = @wiki.repo.commits[3..5].map(&:id)
    assert_equal commits, @wiki.log(:page => 2).map(&:id)
  end

  test "list pages" do
    pages = @wiki.pages
    assert_equal \
      ['Bilbo-Baggins.md', 'Boromir.md', 'Elrond.md', 'Eye-Of-Sauron.md', 'Hobbit.md', 'Home.textile', 'My-Precious.md', 'RingBearers.md', 'Samwise Gamgee.mediawiki', 'todo.txt'],
      pages.map(&:filename).sort
  end

  test "list files" do
    files = @wiki.files
    assert_equal \
      ['Data-Two.csv', 'Data.csv', 'Riddles.rd', 'eye.jpg'],
      files.map(&:filename).sort
  end

  test "counts pages" do
    assert_equal 10, @wiki.size
  end

  test "latest changes in repo" do
    assert_equal @wiki.latest_changes({:max_count => 1}).first.id, "a3e857e03ecc69a99f1dd72dc3f7e0c47602a05a"
  end
  
  test "text_data" do
    wiki = Gollum::Wiki.new(testpath("examples/yubiwa.git"))
    if String.instance_methods.include?(:encoding)
      utf8 = wiki.page("strider").text_data
      assert_equal Encoding::UTF_8, utf8.encoding
      sjis = wiki.page("sjis").text_data(Encoding::SHIFT_JIS)
      assert_equal Encoding::SHIFT_JIS, sjis.encoding
    else
      page = wiki.page("strider")
      assert_equal page.raw_data, page.text_data
    end
  end

  test "gets reverse diff" do
    diff = @wiki.full_reverse_diff('a8ad3c09dd842a3517085bfadd37718856dee813')
    assert_match "a/Mordor/_Sidebar.md", diff
    assert_match "a/_Sidebar.md", diff
  end

  test "gets reverse diff for a page" do
    diff  = @wiki.full_reverse_diff_for('_Sidebar.md', 'a8ad3c09dd842a3517085bfadd37718856dee813')
    regex = /a\/Mordor\/\_Sidebar\.md/
    assert_match "a/_Sidebar.md", diff
    assert_no_match regex, diff
  end

  test "gets scoped page from specified directory" do
    @path = cloned_testpath('examples/lotr.git')
    begin
      wiki  = Gollum::Wiki.new(@path)
      index = wiki.repo.index
      index.read_tree 'master'
      index.add('Foobar/Elrond.md', 'Baz')
      index.commit 'Add Foobar/Elrond.', [wiki.repo.head.commit], Gollum::Git::Actor.new('Tom Preston-Werner', 'tom@github.com')

      assert_equal 'Rivendell/Elrond.md', wiki.page('Elrond', nil, 'Rivendell').path
      # test paged as well.
      assert_equal 'Foobar/Elrond.md', wiki.paged('Elrond', 'Foobar').path
    ensure
      FileUtils.rm_rf(@path)
    end
  end
end

context "Wiki page previewing" do
  setup do
    @path                        = testpath("examples/lotr.git")
    Gollum::Wiki.default_options = { :universal_toc => false }
    @wiki                        = Gollum::Wiki.new(@path)
  end

  test "preview_page" do
    page = @wiki.preview_page("Test", "# Bilbo", :markdown)
    assert_equal "# Bilbo", page.raw_data
    assert_html_equal "<h1><a class=\"anchor\" id=\"bilbo\" href=\"#bilbo\"><i class=\"fa fa-link\"></i></a>Bilbo</h1>", page.formatted_data
    assert_equal "Test.md", page.filename
    assert_equal "Test", page.name

    assert_equal @wiki.repo.commit(@wiki.ref).id, page.version.id
    assert_nil page.last_version
    assert page.versions.empty?
  end
end

context "Wiki TOC" do
  setup do
    @path   = testpath("examples/lotr.git")
    options = { :universal_toc => true }
    @wiki   = Gollum::Wiki.new(@path, options)
  end

  test "empty TOC" do
    page = @wiki.preview_page("Test", "[[_TOC_]] [[_TOC_|levels = 2]] Bilbo", :markdown)
    assert_html_equal "<p>Bilbo</p>", page.formatted_data
    assert_empty page.toc_data
  end

  test "toc_generation" do
    page = @wiki.preview_page("Test", "# Bilbo", :markdown)
    assert_equal "# Bilbo", page.raw_data
    assert_html_equal "<h1><a class=\"anchor\" id=\"bilbo\" href=\"#bilbo\"><i class=\"fa fa-link\"></i></a>Bilbo</h1>", page.formatted_data
    assert_html_equal %{<div class="toc"><div class="toc-title">Table of Contents</div><ul><li><a href="#bilbo">Bilbo</a></li></ul></div>}, page.toc_data
  end

  test "TOC with levels" do
    content = <<-MARKDOWN
# Ecthelion

## Denethor

### Boromir

### Faramir
    MARKDOWN

    formatted = <<-HTML
<h1><a class="anchor" id="ecthelion" href="#ecthelion"><i class="fa fa-link"></i></a>Ecthelion</h1>
<h2><a class="anchor" id="ecthelion_denethor" href="#ecthelion_denethor"><i class="fa fa-link"></i></a>Denethor</h2>
<h3><a class="anchor" id="ecthelion_denethor_boromir" href="#ecthelion_denethor_boromir"><i class="fa fa-link"></i></a>Boromir</h3>
<h3><a class="anchor" id="ecthelion_denethor_faramir" href="#ecthelion_denethor_faramir"><i class="fa fa-link"></i></a>Faramir</h3>
    HTML

    page_level0 = @wiki.preview_page("Test", "[[_TOC_ | levels=0]] \n\n" + content, :markdown)
    toc_formatted_level0 = <<-HTML
<p><div class="toc"><div class="toc-title">Table of Contents</div></div></p>
    HTML
    assert_html_equal toc_formatted_level0 + formatted, page_level0.formatted_data

    page_level1 = @wiki.preview_page("Test", "[[_TOC_ | levels=1]] \n\n" + content, :markdown)
    toc_formatted_level1 = <<-HTML
<p><div class="toc">
<div class="toc-title">Table of Contents</div>
<ul><li><a href="#ecthelion">Ecthelion</a></li></ul>
</div></p>
    HTML
    assert_html_equal toc_formatted_level1 + formatted, page_level1.formatted_data

    page_level2 = @wiki.preview_page("Test", "[[_TOC_ |levels = 2]] \n\n" + content, :markdown)
    toc_formatted_level2 = <<-HTML
<p><div class="toc">
<div class="toc-title">Table of Contents</div>
<ul><li><a href="#ecthelion">Ecthelion</a>
<ul><li><a href="#ecthelion_denethor">Denethor</a></li></ul>
</li></ul>
</div></p>
    HTML
    assert_html_equal toc_formatted_level2 + formatted, page_level2.formatted_data

    page_level3 = @wiki.preview_page("Test", "[[_TOC_ |levels = 3]] \n\n" + content, :markdown)
    page_level4 = @wiki.preview_page("Test", "[[_TOC_ |levels = 4]] \n\n" + content, :markdown)
    page_fulltoc = @wiki.preview_page("Test", "[[_TOC_]] \n\n" + content, :markdown)
    toc_formatted_full = <<-HTML
<p><div class="toc">
<div class="toc-title">Table of Contents</div>
<ul>
  <li>
    <a href="#ecthelion">Ecthelion</a>
    <ul>
      <li><a href="#ecthelion_denethor">Denethor</a>
    <ul>
      <li><a href="#ecthelion_denethor_boromir">Boromir</a></li>
      <li><a href="#ecthelion_denethor_faramir">Faramir</a></li>
    </ul>
  </li></ul>
</li></ul>
</div></p>
    HTML
    assert_html_equal toc_formatted_full + formatted, page_level3.formatted_data
    assert_html_equal toc_formatted_full + formatted, page_level3.formatted_data
    assert_html_equal toc_formatted_full + formatted, page_fulltoc.formatted_data

  end

  # Ensure ' creates valid links in TOC
  # Incorrect: <a href=\"#a\" b=\"\">
  #   Correct: <a href=\"#a'b\">
  test "' in link" do
    page = @wiki.preview_page("Test", "# a'b", :markdown)
    assert_equal "# a'b", page.raw_data
    assert_html_equal "<h1><a class=\"anchor\" id=\"a-b\" href=\"#a-b\"><i class=\"fa fa-link\"></i></a>a'b</h1>", page.formatted_data
    assert_html_equal %{<div class=\"toc\"><div class=\"toc-title\">Table of Contents</div><ul><li><a href=\"#a-b\">a'b</a></li></ul></div>}, page.toc_data
  end
end

context "Wiki TOC in _Sidebar.md" do
  setup do
    @path = testpath("examples/test.git")
    FileUtils.rm_rf(@path)
    Gollum::Git::Repo.init_bare(@path)
    options = { :universal_toc => true }
    @wiki = Class.new(Gollum::Wiki).new(@path, options)
  end
  
  test "_Sidebar.md with [[_TOC_]] renders TOC" do
    cd = commit_details
    @wiki.write_page("Gollum", :markdown, "# Gollum", cd)
    page = @wiki.page("Gollum")
    @wiki.write_page("_Sidebar", :markdown, "[[_TOC_]]", cd)
    sidebar = @wiki.page("_Sidebar")
    sidebar.parent_page = page
    assert_not_equal "\n", sidebar.formatted_data
    assert_html_equal "<p><div class=\"toc\"><div class=\"toc-title\">Table of Contents</div><ul><li><a href=\"#gollum\">Gollum</a></li></ul></div></p>\n", sidebar.formatted_data
  end
  
  teardown do
    FileUtils.rm_r(File.join(File.dirname(__FILE__), *%w(examples test.git)))
  end
end

context "Wiki page writing" do
  setup do
    @path = testpath("examples/test.git")
    FileUtils.rm_rf(@path)
    Gollum::Git::Repo.init_bare(@path)
    @wiki = Gollum::Wiki.new(@path)
  end

  test "write_page" do
    cd = commit_details
    @wiki.write_page("Gollum", :markdown, "# Gollum", cd)
    assert_equal 1, @wiki.repo.commits.size
    assert_equal cd[:message], @wiki.repo.commits.first.message
    assert_equal cd[:name], @wiki.repo.commits.first.author.name
    assert_equal cd[:email], @wiki.repo.commits.first.author.email

    cd2 = { :message => "Updating Bilbo", :author => "Samwise" }
    @wiki.write_page("Bilbo", :markdown, "# Bilbo", cd2)

    commits      = @wiki.repo.commits
    # FIXME Grit commits ordering is not predictable. See #13.
    # The following line should be: commit = commits.first
    first_commit = commits.find { |c| c.message == "Updating Bilbo" }

    assert_equal 2, commits.size
    assert_equal cd2[:message], first_commit.message
    assert_equal cd2[:name], first_commit.author.name
    assert_equal cd2[:email], first_commit.author.email
    assert @wiki.page("Bilbo")
    assert @wiki.page("Gollum")
  end

  test "write page is not allowed to overwrite file" do
    @wiki.write_page("Abc-Def", :markdown, "# Gollum", commit_details)
    assert_raises Gollum::DuplicatePageError do
      @wiki.write_page("ABC DEF", :textile, "# Gollum", commit_details)
    end
  end

  test "write_page does not mutate input parameters" do
    name = "Hello There"
    @wiki.write_page(name, :markdown, 'content', commit_details)
    assert_equal name, "Hello There"
  end

  test "update_page" do
    @wiki.write_page("Gollum", :markdown, "# Gollum", commit_details)
    page = @wiki.page("Gollum")
    @wiki.update_page(page, page.name, :markdown, "# Smeagol", {
        :message => "Leave now, and never come back!",
        :name    => "Smeagol",
        :email   => "smeagol@example.org"
    })

    commits      = @wiki.repo.commits
    # FIXME Grit commits ordering is not predictable. See #13.
    # The following line should be: first_commit = commits.first
    first_commit = commits.find { |c| c.author.name == "Smeagol" }

    assert_equal 2, commits.size
    assert_equal "# Smeagol", @wiki.page("Gollum").raw_data
    assert_equal "Leave now, and never come back!", first_commit.message
    assert_equal "Smeagol", first_commit.author.name
    assert_equal "smeagol@example.org", first_commit.author.email
  end

  test "update page is not allowed to overwrite file with name change" do
    @wiki.write_page("Gollum", :markdown, "# Gollum", commit_details)
    @wiki.write_page("Smeagel", :markdown, "# Smeagel", commit_details)
    page = @wiki.page("Gollum")
    assert_raises Gollum::DuplicatePageError do
      @wiki.update_page(page, 'Smeagel', :markdown, "h1. Gollum", commit_details)
    end
  end

  if $METADATA
    test "page title override with metadata" do
      @wiki.write_page("Gollum", :markdown, "<!-- --- title: Over -->", commit_details)

      page = @wiki.page("Gollum")

      assert_equal 'Over', page.url_path_title
    end
  end

  test "update page with format change" do
    @wiki.write_page("Gollum", :markdown, "# Gollum", commit_details)

    assert_equal :markdown, @wiki.page("Gollum").format

    page = @wiki.page("Gollum")
    @wiki.update_page(page, page.name, :textile, "h1. Gollum", commit_details)

    assert_equal 2, @wiki.repo.commits.size
    assert_equal :textile, @wiki.page("Gollum").format
    assert_equal "h1. Gollum", @wiki.page("Gollum").raw_data
  end

  test "update page with name change" do
    @wiki.write_page("Gollum", :markdown, "# Gollum", commit_details)

    assert_equal :markdown, @wiki.page("Gollum").format

    page = @wiki.page("Gollum")
    @wiki.update_page(page, 'Smeagol', :markdown, "h1. Gollum", commit_details)

    assert_equal 2, @wiki.repo.commits.size
    assert_equal "h1. Gollum", @wiki.page("Smeagol").raw_data
  end

  test "update page with name and format change" do
    @wiki.write_page("Gollum", :markdown, "# Gollum", commit_details)

    assert_equal :markdown, @wiki.page("Gollum").format

    page = @wiki.page("Gollum")
    @wiki.update_page(page, 'Smeagol', :textile, "h1. Gollum", commit_details)

    assert_equal 2, @wiki.repo.commits.size
    assert_equal :textile, @wiki.page("Smeagol").format
    assert_equal "h1. Gollum", @wiki.page("Smeagol").raw_data
  end

  test "update nested page with format change" do
    index = @wiki.repo.index
    index.add("lotr/Gollum.md", "# Gollum")
    index.commit("Add nested page")

    page = @wiki.page("Gollum")
    assert_equal :markdown, @wiki.page("Gollum").format
    @wiki.update_page(page, page.name, :textile, "h1. Gollum", commit_details)

    page = @wiki.page("Gollum")
    assert_equal "lotr/Gollum.textile", page.path
    assert_equal :textile, page.format
    assert_equal "h1. Gollum", page.raw_data
  end

  test "delete root page" do
    @wiki.write_page("Gollum", :markdown, "# Gollum", commit_details)

    page = @wiki.page("Gollum")
    @wiki.delete_page(page, commit_details)

    assert_equal 2, @wiki.repo.commits.size
    assert_nil @wiki.page("Gollum")
  end

  test "delete nested page" do
    index = @wiki.repo.index
    index.add("greek/Bilbo-Baggins.md", "hi")
    index.add("Gollum.md", "hi")
    index.commit("Add alpha.jpg")

    page = @wiki.page("Bilbo-Baggins")
    assert page
    @wiki.delete_page(page, commit_details)

    assert_equal 2, @wiki.repo.commits.size
    assert_nil @wiki.page("Bilbo-Baggins")

    assert @wiki.page("Gollum")
  end

  teardown do
    FileUtils.rm_r(File.join(File.dirname(__FILE__), *%w(examples test.git)))
  end
end

context "Wiki search" do
  setup do
    @path = testpath("examples/test.git")
    FileUtils.rm_rf(@path)
    Gollum::Git::Repo.init_bare(@path)
    @wiki = Class.new(Gollum::Wiki).new(@path)
    @wiki.write_page("bar", :markdown, "bar", commit_details)
    @wiki.write_page("filename:with:colons", :markdown, "# Filename with colons", commit_details)
    @wiki.write_page("foo", :markdown, "# File with query in contents and filename\nfoo", commit_details)
  end
  
  test "search results should be able to return a filename with an embedded colon" do
    results = @wiki.search("colons")
    assert_not_nil results
    assert_equal "filename:with:colons", results.first[:name]
    assert_equal 2, results.first[:count]
  end

  test "search results should make the content/filename search additive" do
    # There is a file that contains the word 'foo' and is called 'foo', so it should
    # have a count of 2, not 1...
    results = @wiki.search("foo")
    assert_equal 2, results.first[:count]
  end

  test "search results should not include files that do not match the query" do
    results = @wiki.search("foo")
    assert_equal 1, results.size
    assert_equal "foo", results.first[:name]
  end
  
  teardown do
    FileUtils.rm_r(File.join(File.dirname(__FILE__), *%w(examples test.git)))
  end
end

context "Wiki page writing with whitespace (filename contains whitespace)" do
  setup do
    @path = cloned_testpath("examples/lotr.git")
    @wiki = Gollum::Wiki.new(@path)
  end

  test "update_page" do
    assert_equal :mediawiki, @wiki.page("Samwise Gamgee").format
    assert_equal "Samwise Gamgee.mediawiki", @wiki.page("Samwise Gamgee").filename

    page = @wiki.page("Samwise Gamgee")
    @wiki.update_page(page, page.name, :textile, "h1. Samwise Gamgee2", commit_details)

    assert_equal :textile, @wiki.page("Samwise Gamgee").format
    assert_equal "h1. Samwise Gamgee2", @wiki.page("Samwise Gamgee").raw_data
    assert_equal "Samwise-Gamgee.textile", @wiki.page("Samwise Gamgee").filename
  end

  test "update page with format change, verify non-canonicalization of filename,  where filename contains Whitespace" do
    assert_equal :mediawiki, @wiki.page("Samwise Gamgee").format
    assert_equal "Samwise Gamgee.mediawiki", @wiki.page("Samwise Gamgee").filename

    page = @wiki.page("Samwise Gamgee")
    @wiki.update_page(page, page.name, :textile, "h1. Samwise Gamgee", commit_details)

    assert_equal :textile, @wiki.page("Samwise Gamgee").format
    assert_equal "h1. Samwise Gamgee", @wiki.page("Samwise Gamgee").raw_data
    assert_equal "Samwise-Gamgee.textile", @wiki.page("Samwise Gamgee").filename
  end

  test "update page with name change, verify canonicalization of filename, where filename contains Whitespace" do
    assert_equal :mediawiki, @wiki.page("Samwise Gamgee").format
    assert_equal "Samwise Gamgee.mediawiki", @wiki.page("Samwise Gamgee").filename

    page = @wiki.page("Samwise Gamgee")
    @wiki.update_page(page, 'Sam Gamgee', :textile, "h1. Samwise Gamgee", commit_details)

    assert_equal "h1. Samwise Gamgee", @wiki.page("Sam Gamgee").raw_data
    assert_equal "Sam-Gamgee.textile", @wiki.page("Sam Gamgee").filename
  end

  test "update page with name and format change, verify canonicalization of filename, where filename contains Whitespace" do
    assert_equal :mediawiki, @wiki.page("Samwise Gamgee").format
    assert_equal "Samwise Gamgee.mediawiki", @wiki.page("Samwise Gamgee").filename

    page = @wiki.page("Samwise Gamgee")
    @wiki.update_page(page, 'Sam Gamgee', :textile, "h1. Samwise Gamgee", commit_details)

    assert_equal :textile, @wiki.page("Sam Gamgee").format
    assert_equal "h1. Samwise Gamgee", @wiki.page("Sam Gamgee").raw_data
    assert_equal "Sam-Gamgee.textile", @wiki.page("Sam Gamgee").filename
  end

  teardown do
    FileUtils.rm_rf(@path)
  end
end

context "Wiki sync with working directory" do
  setup do
    @path = testpath('examples/wdtest')
    Gollum::Git::Repo.init(@path)
    @wiki = Gollum::Wiki.new(@path)
  end

  test "write a page" do
    @wiki.write_page("New Page", :markdown, "Hi", commit_details)
    assert_equal "Hi", File.read(File.join(@path, "New-Page.md"))
  end

  test "write a page in subdirectory" do
    @wiki.write_page("New Page", :markdown, "Hi", commit_details, "Subdirectory")
    assert_equal "Hi", File.read(File.join(@path, "Subdirectory", "New-Page.md"))
  end

  test "update a page with same name and format" do
    @wiki.write_page("New Page", :markdown, "Hi", commit_details)
    page = @wiki.page("New Page")
    @wiki.update_page(page, page.name, page.format, "Bye", commit_details)
    assert_equal "Bye", File.read(File.join(@path, "New-Page.md"))
  end

  test "update a page with different name and same format" do
    @wiki.write_page("New Page", :markdown, "Hi", commit_details)
    page = @wiki.page("New Page")
    @wiki.update_page(page, "New Page 2", page.format, "Bye", commit_details)
    assert_equal "Bye", File.read(File.join(@path, "New-Page-2.md"))
    assert !File.exist?(File.join(@path, "New-Page.md"))
  end

  test "update a page with same name and different format" do
    @wiki.write_page("New Page", :markdown, "Hi", commit_details)
    page = @wiki.page("New Page")
    @wiki.update_page(page, page.name, :textile, "Bye", commit_details)
    assert_equal "Bye", File.read(File.join(@path, "New-Page.textile"))
    assert !File.exist?(File.join(@path, "New-Page.md"))
  end

  test "update a page with different name and different format" do
    @wiki.write_page("New Page", :markdown, "Hi", commit_details)
    page = @wiki.page("New Page")
    @wiki.update_page(page, "New Page 2", :textile, "Bye", commit_details)
    assert_equal "Bye", File.read(File.join(@path, "New-Page-2.textile"))
    assert !File.exist?(File.join(@path, "New-Page.md"))
  end

  test "delete a page" do
    @wiki.write_page("New Page", :markdown, "Hi", commit_details)
    page = @wiki.page("New Page")
    @wiki.delete_page(page, commit_details)
    assert !File.exist?(File.join(@path, "New-Page.md"))
  end

  teardown do
    FileUtils.rm_r(@path)
  end
end

context "Wiki sync with working directory (filename contains whitespace)" do
  setup do
    @path = cloned_testpath("examples/lotr.git")
    @wiki = Gollum::Wiki.new(@path)
  end
  test "update a page with same name and format" do
    page = @wiki.page("Samwise Gamgee")
    @wiki.update_page(page, page.name, page.format, "What we need is a few good taters.", commit_details)
    assert_equal "What we need is a few good taters.", File.read(File.join(@path, "Samwise Gamgee.mediawiki"))
  end

  test "update a page with different name and same format" do
    page = @wiki.page("Samwise Gamgee")
    @wiki.update_page(page, "Sam Gamgee", page.format, "What we need is a few good taters.", commit_details)
    assert_equal "What we need is a few good taters.", File.read(File.join(@path, "Sam-Gamgee.mediawiki"))
    assert !File.exist?(File.join(@path, "Samwise Gamgee"))
  end

  test "update a page with same name and different format" do
    page = @wiki.page("Samwise Gamgee")
    @wiki.update_page(page, page.name, :textile, "What we need is a few good taters.", commit_details)
    assert_equal "What we need is a few good taters.", File.read(File.join(@path, "Samwise-Gamgee.textile"))
    assert !File.exist?(File.join(@path, "Samwise-Gamgee.mediawiki"))
  end

  test "update a page with different name and different format" do
    page = @wiki.page("Samwise Gamgee")
    @wiki.update_page(page, "Sam Gamgee", :textile, "What we need is a few good taters.", commit_details)
    assert_equal "What we need is a few good taters.", File.read(File.join(@path, "Sam-Gamgee.textile"))
    assert !File.exist?(File.join(@path, "Samwise Gamgee.mediawiki"))
  end

  test "delete a page" do
    page = @wiki.page("Samwise Gamgee")
    @wiki.delete_page(page, commit_details)
    assert !File.exist?(File.join(@path, "Samwise Gamgee.mediawiki"))
  end

  teardown do
    FileUtils.rm_r(@path)
  end
end

context "page_file_dir option" do
  setup do
    @path          = cloned_testpath('examples/page_file_dir')
    @page_file_dir = 'docs'
    @wiki          = Gollum::Wiki.new(@path, :page_file_dir => @page_file_dir)
  end

  test "write a page in sub directory" do
    @wiki.write_page("New Page", :markdown, "Hi", commit_details)
    assert_equal "Hi", File.read(File.join(@path, @page_file_dir, "New-Page.md"))
    assert !File.exist?(File.join(@path, "New-Page.md"))
  end

  test "edit a page in a sub directory" do
    page = @wiki.page('foo')
    @wiki.update_page(page, page.name, page.format, 'new contents', commit_details)
  end

  test "a file in page file dir should be found" do
    assert @wiki.page("foo")
  end

  test "a file out of page file dir should not be found" do
    assert !@wiki.page("bar")
  end

  test "search results should be restricted in page filer dir" do
    results = @wiki.search("foo")
    assert_equal 1, results.size
    assert_equal "docs/foo", results[0][:name]
  end

  teardown do
    FileUtils.rm_r(@path)
  end
end

context "Wiki page writing with different branch" do
  setup do
    @path = testpath("examples/test.git")
    FileUtils.rm_rf(@path)
    @repo = Gollum::Git::Repo.init_bare(@path)
    @wiki = Gollum::Wiki.new(@path)

    # We need an initial commit to create the master branch
    # before we can create new branches
    cd    = commit_details
    @wiki.write_page("Gollum", :markdown, "# Gollum", cd)

    # Create our test branch and check it out
    @repo.update_ref("test", @repo.commits.first.id)
    @branch = Gollum::Wiki.new(@path, :ref => "test")
  end

  teardown do
    FileUtils.rm_rf(@path)
  end

  test "write_page" do
    @branch.write_page("Bilbo", :markdown, "# Bilbo", commit_details)
    assert @branch.page("Bilbo")
    assert @wiki.page("Gollum")

    assert_equal 1, @wiki.repo.commits.size
    assert_equal 1, @branch.repo.commits.size

    assert_equal nil, @wiki.page("Bilbo")
  end
end

context "Renames directory traversal" do
  setup do
    @path = cloned_testpath("examples/revert.git")
    @wiki = Gollum::Wiki.new(@path)
  end

  teardown do
    FileUtils.rm_rf(@path)
  end

  test "rename aborts on nil" do
    res = @wiki.rename_page(@wiki.page("some-super-fake-page"), "B", rename_commit_details)
    assert !res, "rename did not abort with non-existant page"
    res = @wiki.rename_page(@wiki.page("B"), "", rename_commit_details)
    assert !res, "rename did not abort with empty rename"
    res = @wiki.rename_page(@wiki.page("B"), nil, rename_commit_details)
    assert !res, "rename did not abort with nil rename"
  end

  test "rename page no-act" do
    # Make sure renames don't do anything if the name is the same.
    # B.md => B.md
    res = @wiki.rename_page(@wiki.page("B"), "B", rename_commit_details)
    assert !res, "NOOP rename did not abort"
  end

  test "rename page without directories" do
    # Make sure renames work with relative paths.
    source = @wiki.page("B")

    # B.md => C.md
    assert @wiki.rename_page(source, "C", rename_commit_details)

    assert_renamed source, @wiki.page("C")
  end

  test "rename page containing space without directories" do
    # Make sure renames involving spaces work with relative paths.
    source = @wiki.page("B")

    # B.md => C D.md
    assert @wiki.rename_page(source, "C D", rename_commit_details)

    assert_renamed source, @wiki.page("C D")
  end

  test "rename page with subdirs" do
    # Make sure renames in subdirectories happen ok
    source = @wiki.paged("H", "G")

    # G/H.md => G/F.md
    assert @wiki.rename_page(source, "G/F", rename_commit_details)

    assert_renamed source, @wiki.paged("F", "G")
  end

  test "rename page containing space with subdir" do
    # Make sure renames involving spaces in subdirectories happen ok
    source = @wiki.paged("H", "G")

    # G/H.md => G/F H.md
    assert @wiki.rename_page(source, "G/F H", rename_commit_details)

    assert_renamed source, @wiki.paged("F H", "G")
  end

  test "rename page absolute path is still no-act" do
    # Make sure renames don't do anything if the name is the same.

    # B.md => B.md
    res = @wiki.rename_page(@wiki.page("B"), "/B", rename_commit_details)
    assert !res, "NOOP rename did not abort"
  end

  test "rename page absolute path NOOPs ok" do
    # Make sure renames don't do anything if the name is the same and we are in a subdirectory.
    source = @wiki.paged("H", "G")

    # G/H.md => G/H.md
    res    = @wiki.rename_page(source, "/G/H", rename_commit_details)
    assert !res, "NOOP rename did not abort"
  end

  test "rename page absolute directory" do
    # Make sure renames work with absolute paths.
    source = @wiki.page("B")

    # B.md => C.md
    assert @wiki.rename_page(source, "/C", rename_commit_details)

    assert_renamed source, @wiki.page("C")
  end

  test "rename page with space absolute directory" do
    # Make sure renames involving spaces work with absolute paths.
    source = @wiki.page("B")

    # B.md => C D.md
    assert @wiki.rename_page(source, "/C D", rename_commit_details)

    assert_renamed source, @wiki.page("C D")
  end

  test "rename page absolute directory with subdirs" do
    # Make sure renames in subdirectories happen ok
    source = @wiki.paged("H", "G")

    # G/H.md => G/F.md
    assert @wiki.rename_page(source, "/G/F", rename_commit_details)

    assert_renamed source, @wiki.paged("F", "G")
  end

  test "rename page containing space absolute directory with subdir" do
    # Make sure renames involving spaces in subdirectories happen ok
    source = @wiki.paged("H", "G")

    # G/H.md => G/F H.md
    assert @wiki.rename_page(source, "/G/F H", rename_commit_details)

    assert_renamed source, @wiki.paged("F H", "G")
  end

  test "rename page relative directory with new dir creation" do
    # Make sure renames in subdirectories create more subdirectories ok
    source = @wiki.paged("H", "G")

    # G/H.md => G/K/F.md
    assert @wiki.rename_page(source, "K/F", rename_commit_details)

    new_page = @wiki.paged("F", "K")
    assert_not_nil new_page
    assert_renamed source, new_page
  end

  test "rename page relative directory with new dir creation containing space" do
    # Make sure renames involving spaces in subdirectories create more subdirectories ok
    source = @wiki.paged("H", "G")

    # G/H.md => G/K L/F.md
    assert @wiki.rename_page(source, "K L/F", rename_commit_details)

    new_page = @wiki.paged("F", "K L")
    assert_not_nil new_page
    assert_renamed source, new_page
  end

  test "rename page absolute directory with subdir creation" do
    # Make sure renames in subdirectories create more subdirectories ok
    source = @wiki.paged("H", "G")

    # G/H.md => G/K/F.md
    assert @wiki.rename_page(source, "/G/K/F", rename_commit_details)

    new_page = @wiki.paged("F", "G/K")
    assert_not_nil new_page
    assert_renamed source, new_page
  end

  test "rename page absolute directory with subdir creation containing space" do
    # Make sure renames involving spaces in subdirectories create more subdirectories ok
    source = @wiki.paged("H", "G")

    # G/H.md => G/K L/F.md
    assert @wiki.rename_page(source, "/G/K L/F", rename_commit_details)

    new_page = @wiki.paged("F", "G/K L")
    assert_not_nil new_page
    assert_renamed source, new_page
  end

  test "rename page with a name of an already existing page does not clobber that page" do
    @wiki.write_page("Gollum", :markdown, "# Gollum", commit_details)
    @wiki.write_page("Smeagel", :markdown, "# Smeagel", commit_details)
    page = @wiki.page("Gollum")
    assert_raises Gollum::DuplicatePageError do
      @wiki.rename_page(page, 'Smeagel', rename_commit_details)
    end
  end

  def assert_renamed(page_source, page_target)
    @wiki.clear_cache
    assert_nil @wiki.paged(page_source.name, page_source.path)

    assert_equal "INITIAL\n\nSPAM2\n", page_target.raw_data
    assert_equal "def", page_target.version.message
    assert_equal "Smeagol", page_target.version.author.name
    assert_equal "smeagol@example.org", page_target.version.author.email
    assert_not_equal page_source.version.sha, page_target.version.sha
  end

  def rename_commit_details
    { :message => "def", :name => "Smeagol", :email => "smeagol@example.org" }
  end
end

context "Wiki subclassing" do
  setup do
    @path = testpath("examples/test.git")
    FileUtils.rm_rf(@path)
    Gollum::Git::Repo.init_bare(@path)
    @wiki = Class.new(Gollum::Wiki).new(@path)
  end

  test "wiki page can be written by subclass" do
    details = commit_details
    @wiki.write_page("Gollum", :markdown, "# Gollum", details)
    page = @wiki.page("Gollum")
    first_commit = @wiki.repo.commits.first

    assert_equal 1, @wiki.repo.commits.size
    assert_equal details[:name], first_commit.author.name
    assert_equal details[:email], first_commit.author.email
    assert_equal details[:message], first_commit.message
    assert_equal "# Gollum", page.raw_data
  end

  test "wiki page can be updated by subclass" do
    @wiki.write_page("Gollum", :markdown, "# Gollum", commit_details)
    page = @wiki.page("Gollum")

    @wiki.update_page(page, page.name, :markdown, "# Smeagol", {
        :name    => "Smeagol",
        :email   => "smeagol@example.org",
        :message => "Leave now, and never come back!"
    })
    page = @wiki.page("Gollum")
    first_commit = @wiki.repo.commits.find { |c| c.author.name == "Smeagol" }

    assert_equal 2, @wiki.repo.commits.size
    assert_equal "Smeagol", first_commit.author.name
    assert_equal "smeagol@example.org", first_commit.author.email
    assert_equal "Leave now, and never come back!", first_commit.message
    assert_equal "# Smeagol", page.raw_data
  end

  test "wiki page can be deleted by subclass" do
    @wiki.write_page("Gollum", :markdown, "# Gollum", commit_details)
    page = @wiki.page("Gollum")

    @wiki.delete_page(page, commit_details)
    page = @wiki.page("Gollum")

    assert_equal 2, @wiki.repo.commits.size
    assert_nil page
  end

  teardown do
    FileUtils.rm_r(File.join(File.dirname(__FILE__), *%w(examples test.git)))
  end
end
