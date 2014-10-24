require 'spec_helper'

include Warden::Test::Helpers

describe 'Saved List Interface' do

  before(:each) do
    @autodidact = FactoryGirl.create(:user, login: 'autodidact')
    @blatteroon = FactoryGirl.create(:user, login: 'blatteroon')
  end

  describe 'share by email' do
    before(:each) do
      feature_login @autodidact
    end
    it 'supports an email function, directly' do
      visit email_savedlist_path(id: '12_345')
      expect(page).to have_text('Share selected item(s) via email')
      within('#email_form') do fill_in 'to', with: 'marquis@columbia.edu' end
      (within('#email_form') do find('button[type=submit]') end).click
    end

    it 'supports an email function, via JS modal', js: true do
      @list=SavedList.create!(owner: @autodidact.login, name: 'george')
      @list.saved_list_items=[SavedListItem.new(item_key: "10922430")]
      visit '/lists/autodidact/george/'
      (page.find("#item_select_10922430")).set(true)
      find('a', :text=>'Selected List Items...').click
      find('a', :text=>'Send to Email').click
      (within('.btn-toolbar', visible: false) do find('#emailLink', visible: false) end).trigger('click')
      expect(page).to have_text('Share selected item(s) via email')

      page.should have_css('.modal-dialog .modal-content .modal-header')

      find('.modal-header').should have_text('Share selected item(s) via email')

      within '#email_form' do
        fill_in 'to', with: 'marquis@columbia.edu'
        fill_in 'message', with: 'testing'
        find('button[type=submit]').click
      end
    end
  end

  it 'Capybara should let us login and logout and login again', xfocus: true do
    # Not yet logged in - navbar shows un-authenticated message
    visit catalog_index_path
    find('#topnavbar').should have_text 'My Library Account'

    # Login as the first user, verify the name shows in the nav bar
    feature_login @autodidact

    visit catalog_index_path
    find('#topnavbar').should have_text @autodidact.login

    # Logout - navbar shows un-authenticated message
    feature_logout
    visit catalog_index_path
    find('#topnavbar').should have_text 'My Library Account'

    # Login as the second user, verify the (second user's) name shows in the nav bar
    feature_login @blatteroon
    visit catalog_index_path
    find('#topnavbar').should have_text @blatteroon.login

    # Logout - navbar shows un-authenticated message
    feature_logout
    visit catalog_index_path
    find('#topnavbar').should have_text 'My Library Account'
  end

  it 'should give no access to anonymous users' do
    visit '/lists'
    # page.save_and_open_page # debug
    # page.should have_text('Login required to access Saved Lists')
    # In this context, the WIND redirect happens against the local
    # server, giving a 404.
    page.should have_text('Invalid URL: /login')

    visit '/saved_lists/1/edit'
    # page.save_and_open_page # debugI
    # page.should have_text('Login required to access Saved Lists')
    page.should have_text('Invalid URL: /login')
  end

  it 'should protect private lists and share public lists', js: true do

    # Use Warden::Test::Helpers for Feature testing
    feature_login @autodidact

    # First, visit my Lists page.  Should see the default list, "Bookbag"
    visit '/lists'
    # page.save_and_open_page # debug
    page.should have_text('Saved Lists')
    page.should have_text('Bookbag')

    # Next, do a catalog search, Add all found items to our Bookbag
    visit catalog_index_path('q' => 'aardvark war')
    click_link('Selected Items')
    click_link('Select All Items')
    click_link('Selected Items')
    click_link('Add to My Saved List')

    # Now, go back again to my Lists page.  I should see the just-added records
    visit '/lists'
    # page.save_and_open_page # debug
    page.should have_text('aardvark')

    # Move all these items off to a different named list
    click_link('Selected List Items')
    click_link('Select All Items')
    click_link('Move Selected Items')
    within('#new_list_form') do
      fill_in 'new_list_name', with: 'aardvark'
      click_button('new_list_submit')
    end
    # page.save_and_open_page # debug

    # We should be redirected to the new list, defaulting to private
    within('.savedlist_header') do
      page.should have_text('aardvark')
      page.should have_text('edit list details')
      first('span.label', text: 'private')
    end

    # Make this list public
    click_link 'edit list details'
    page.should have_text('Editing list')
    choose('public')
    click_button 'Save'

    # Confirm that this change took affect.
    page.should have_text('Saved Lists')
    within('.savedlist_header') do
      page.should have_text('aardvark')
      page.should have_text('edit list details')
      first('span.label', text: 'public')
    end

    # Next, do a new, different catalog search,
    # Add all found items to our Bookbag,
    # which should still be private
    visit catalog_index_path('q' => 'aardvark war')
    click_link('Selected Items')
    click_link('Select All Items')
    click_link('Selected Items')
    click_link('Add to My Saved List')

    # visit catalog_index_path()

    #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #
    # # Login as a different user
    #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #  #

    feature_login @blatteroon
    visit catalog_index_path
    # save_and_open_page

    # Try to visit a non-existant list
    visit '/lists/NoSuchUser/NoSuchList'
    page.should have_text('Cannot access list NoSuchUser/NoSuchList')

    # save_and_open_page # debug

    # # Try to edit a non-existant list
    # visit '/saved_lists/9999999/edit'
    # page.should have_text('Cannot access list')

    # # Try to visit the first user's public list
    # visit "/lists/#{@audodidact.login}/aardvark"
    # within('.savedlist_header') do
    #   page.should have_text('aardvark')
    #   first('span.label', :text => 'public')
    # end

    # # Try to visit the first user's private list
    # visit "/lists/#{@first_user_name}/bookbag"
    # page.should have_text("Cannot access list #{@first_user_name}/bookbag")
    #

  end

end
