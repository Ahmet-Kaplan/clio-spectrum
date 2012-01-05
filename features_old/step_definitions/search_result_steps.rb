# Steps to check search results
require File.expand_path(File.dirname(__FILE__) + '/../support/env')
#require File.expand_path(File.dirname(__FILE__) + '/webrat_steps')

include Blacklight::SolrHelper

# TODO:  this is checking if the index URL is in stanford domain;  it
#   should be checking if there is particular content in the index that
#   identifies the data properly
#      more than 5,500,000  docs;  has certain docs(s) ...
Given /a SOLR index with Columbia MARC data/i do
  Blacklight.solr_config[:url].should =~ /(.*)\.columbia.edu/
end

# search query can have escaped quotes anywhere
When /^I search (catalog|articles) with "([^\"]*?)"$/ do |source, query|
  execute_query(source, query)
end

=begin
# <b>DEPRECATED:</b> Please use <tt>I fill in the search box with "\"query\""</tt> instead.
# search query can be a phrase
When /^I fill in the search box with "([^\"]*)"( as a phrase)?$/ do |query, phrase|
  if phrase != nil
    query = '"' + query + '"'
  end
  fill_in(:q, :with => query) 
end
=end

Then /^result (\d+) should include "(.*)"$/ do |index, text|
  result = page.all("#documents .document").listify[index.to_i - 1]
  assert result, "Result no #{index} not found"

  assert result.text.include?(text), "#{result.text} does not include #{text}"
end

Then /^I should get results$/ do 
  page.should have_selector("div.document")
end

Then /^I should not get results$/ do 
  page.should_not have_selector("div.document")
end

Then /^I (should not|should) see a "(.*)" xml element$/ do |bool,elem|
  if bool == "should not"
    page.should_not have_selector(elem)
  else
    page.should have_selector(elem)
  end
end

Then /^I should get (at least|at most) (\d+) results?$/i do |comparator, comparison_num|
  number_of_records = get_number_of_results()
  case comparator
  when "at least"
    assert_operator number_of_records, :>=, comparison_num.to_i
  when "at most"
    assert_operator number_of_records, :<=, comparison_num.to_i
  end
end

Then /^I should get (at least|at most) (\d+) total results?$/i do |comparator, comparison_num|
  response.body =~ /(\d+) results?/
  case comparator
    when "at least"
      assert_operator $1.to_i, :>=, comparison_num.to_i 
    when "at most"
      assert_operator $1.to_i, :<=, comparison_num.to_i
  end
end

Then /^I should get ckey (\d+) in the results$/i do |ckey|
  response.should have_tag("a[href*=?]", /view\/#{ckey}/)
end

Then /^I should not get ckey (\d+) in the results$/i do |ckey|
  response.should_not have_tag("a[href*=?]", /^.*#{ckey}.*$/)
end

Then /^I should get ckey (\d+) in the first (\d+) results?$/i do |ckey, max_num|
  pos = get_position_in_result_page(response, ckey) 
  pos.should_not == -1
  pos.should < max_num.to_i
end

Then /^I should not get ckey (\d+) in the first (\d+) results?$/i do |ckey, max_num|
  pos = get_position_in_result_page(response, ckey) 
  if pos != -1
    pos.should >= max_num.to_i
  else
    # for error messages if needed
    pos.should == -1
  end
end

Then /^I should get facet "(.*)" before facet "(.*)"$/ do |facet1,facet2|
  pos1 = get_facet_item_position(response,facet1)
  pos2 = get_facet_item_position(response,facet2)
  pos1.should_not == -1
  pos2.should_not == -1
  pos1.should < pos2
end

Then /^the facet "(.*)" should display$/ do |facet|
  get_facet_item_position(response,facet).should_not == -1
end

Then /^the facet "(.*)" should not display$/ do |facet|
  get_facet_item_position(response,facet).should == -1
end

Then /^I should get ckey (\d+) before ckey (\d+)$/ do |ckey1, ckey2|
  pos1 = get_position_in_result_page(response, ckey1) 
  pos2 = get_position_in_result_page(response, ckey2)
  pos1.should_not == -1
  pos2.should_not == -1
  pos1.should < pos2
end

#Then /^I should get (the same number of|fewer|more) results (?:than|as) a(?:n?) (.*)search for "(.+)"( as a phrase)?$/i do |comparator, type, query, phrase|
Then /^I should get (the same number of|fewer|more) results (?:than|as) a(?:n?) (.*)search for "(.+?)"?$/i do |comparator, type, query|
  case type
    when "author ", "Author "
      search_field = "Author"
    when "title ", "Title "
      search_field = "Title"
    when "subject ", "Subject "
      search_field = "Subject terms"
    else
      search_field = "All Fields"
  end  

  i = get_number_of_results
  
  case comparator
    when "the same number of"
#      get_num_results_for_query(query, search_field, phrase).should == i
      assert_equal get_num_results_for_query('catalog', query, search_field).should, i
    when "fewer"
#      get_num_results_for_query(query, search_field, phrase).should > i
      get_num_results_for_query('catalog', query, search_field).should > i
    when "more"
#      get_num_results_for_query(query, search_field, phrase).should < i
      get_num_results_for_query('catalog', query, search_field).should < i
  end
end

Then /^I should get at least (\d+) of these ckeys in the first (\d+) results: "((?:(?:\d+)(?:, )?)+)"$/i do |how_many, limit, ckey_string|
  count = 0;
  ckeys = ckey_string.split(/, ?/)
  ckeys.each do |ckey|
    pos = get_position_in_result_page(response, ckey)
    if pos != -1 && pos < limit.to_i
      count = count + 1
    end
  end
  count.should >= how_many.to_i
end

Then /^I should get ckey (\d+) and ckey (\d+) within (\d+) positions? of each other$/i do |ckey1, ckey2, how_far|
  pos1 = get_position_in_result_page(response, ckey1) 
  pos2 = get_position_in_result_page(response, ckey2)
  pos1.should_not == -1
  pos2.should_not == -1
  pos2.should <= pos1 + how_far.to_i
end

Then /^I should get result titles that contain "(.*)" as the first (\d+) results?$/i do |target, limit|
  count = 0;
  titles = response.body.scan(/class="index_title">.*<a.*href=.*\/view\/(?:\d+).*>(.*)<\/a>/)
  titles.each do |title|
    if title.to_s.match(/#{target}/i) != nil
      count = count + 1
    else break
    end
  end
  count.should >= limit.to_i
end

Then /^I should not get result author "(.*)" in the first (\d+) results?$/i do |target, limit|
  count = 0;
  authors = response.body.scan(/<dt>Author\/Creator:<\/dt><dd>(.*)<\/dd>/)
  authors.each do |author|
    if author.to_s.match(/#{target}/i) != nil
      break
    else
      count = count + 1
    end
  end
  if limit.to_i > authors.length
    limit = authors.length
  end
  count.should >= limit.to_i
end

Then /^I should see "(.*)" before "(.*)"$/i do |first, second|
  first_ix = response.body.index(first)
  first_ix.should_not be_nil
  second_ix = response.body.index(second, first_ix)
  second_ix.should_not be_nil
  first_ix.should < second_ix
end

Then /I should see "(.*)" (at least|at most|exactly) (.*) times?$/i do |target, comparator, expected_num|
  actual_num = response.body.split(target).length - 1
  case comparator
    when "at least"
      actual_num.should >= expected_num.to_i
    when "at most"
      actual_num.should <= expected_num.to_i
    when "exactly"
      actual_num.should == expected_num.to_i
  end
end

Then /I should see a "(.*)" element with "(.*)" = "(.*)" (at least|at most|exactly) (.*) times?$/i do |target, type, selector,comparator, expected_num|
  actual_num = response.body.scan(/<#{target} #{type}="#{selector}">/).length
  case comparator
    when "at least"
      actual_num.should >= expected_num.to_i
    when "at most"
      actual_num.should <= expected_num.to_i
    when "exactly"
      actual_num.should == expected_num.to_i
  end
end

Then /^I should see tag with class "(.*)" for value "(.*)"$/i do |css_class, value|
  response.should have_selector(".#{css_class}" , :content => value)
end

Then /^I should see a "([^\"]*)" element with "(.*)" = "([^\"]*)" and with "(.*)" inside$/ do |elem,type,id,content|
  if type == "id"
    type = "#"
  elsif type == "class"
    type = "."
  end
  response.should have_selector("#{elem}#{type}#{id}",:content => content)
end

Then /^I should not see a "([^\"]*)" element with "(.*)" = "([^\"]*)" and with "(.*)" inside$/ do |elem,type,id,content|
  if type == "id"
    type = "#"
  elsif type == "class"
    type = "."
  end
  response.should_not have_selector("#{elem}#{type}#{id}",:content => content)
end

Then /^I should see a link element with "(.*)" inside the href and "(.*)" as the link text$/ do |href,content|
  response.body.scan(/<a.*href=".*#{href}.*".*>#{content}<\/a>/).length.should > 0
end

Then /^I should see a "([^\"]*)" element with "(.*)" "([^\"]*)"$/ do |elem,type,imgid|
  if type == "id"
    type = "#"
  elsif type == "class"
    type = "."
  end
  response.should have_selector("#{elem}#{type}#{imgid}")
end

Then /^I should not see a "([^\"]*)" element with "(.*)" "([^\"]*)"$/ do |elem,type,imgid|
  if type == "id"
    type = "#"
  elsif type == "class"
    type = "."
  end
  response.should_not have_selector("#{elem}#{type}#{imgid}")
end

Then /^I (should not|should) see an? "([^\"]*)" element with an? "([^\"]*)" attribute of "([^\"]*)"$/ do |bool,elem,attribute,value|
  if bool == "should not"
    response.should_not have_selector("#{elem}[#{attribute}=#{value}]")
  else
    response.should have_selector("#{elem}[#{attribute}=#{value}]")
  end
end

Then /^I should get callnumber "(.*)" before callnumber "(.*)"$/ do |callnum1, callnum2|
  pos1 = get_callnum_position_in_show_view(response, callnum1) 
  pos2 = get_callnum_position_in_show_view(response, callnum2)
  pos1.should_not == -1
  pos2.should_not == -1
  pos1.should < pos2
end

# The below methods are private
def get_position_in_result_page(response, ckey)
  doc_link_ckeys = page.all(".title a").collect { |e| e['href'].to_s.scan(/\/catalog\/(\d+)/) }.flatten.compact

  doc_link_ckeys.each_with_index do |doc_link_ckey, num|
    if doc_link_ckey.to_s.match(/^#{ckey}$/) != nil
      return num
    end
  end
  -1 # ckey not found in page of results
end

def execute_query(source, query, query_type = 'All Fields')
  
  within ".search_box.#{source}" do
    fill_in("#{source}_q", :with => query.gsub(/\\"/, '"'))
    if has_selector?(".search_box.#{source} select.search_field")
      fill_in("select.search_field", :with => query_type.to_s)
    end
    click_button("Search")
  end
end

#def get_num_results_for_query(query, query_type="Everything", phrase_search=nil) 
def get_num_results_for_query(source, query, query_type="All Fields") 
  execute_query(source, query, query_type)

  get_number_of_results()
end

def get_callnum_position_in_show_view(response, callnum)
  callnumbers = response.body.scan(/<span id="avail_.+?".+?>(.*[^<]*)<span class="off_screen">/).map{|w|w.to_s.strip}
  callnumbers.each_with_index do |callnumber, num|
    if callnumber.to_s.match(/^#{callnum}$/) != nil
      return num
    end
  end
  -1 # ckey not found in page of results
end
def get_facet_item_position(facet_item)
  doc_facets = response.body.scan(/<label for=".*">(.*)<\/label>/)
  doc_facets.each_with_index do |doc_facet, num|
    if doc_facet.to_s.match(/^#{facet_item}$/) != nil
      return num
    end
  end
  -1 # ckey not found in page of results
end

def get_number_of_results
  # really odd way of getting number of docs.  This retuns an array of ODD/EVEN when found in a document class.  This returns the total number of documents
  page.all("div.document").length
end


