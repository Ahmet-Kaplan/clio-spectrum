module Voyager
  module Holdings
    class Record
      attr_reader :holding_id, :location_name, :call_number,
                  :summary_holdings, :public_notes,
                  :shelving_title, :supplements, :indexes,
                  :reproduction_note, :urls, :item_count, :temp_locations,
                  :item_status, :orders, :current_issues, :services,
                  :bibid, :donor_info, :location_note, :temp_loc_flag


      def initialize(mfhd_id, marc, mfhd_status)
        mfhd_status ||= {}

        @bibid = marc['001'].value
        @holding_id = mfhd_id
# raise
        tag852 = nil
        marc.each_by_tag('852') do |this852|
          tag852 = this852 if this852['0'] == mfhd_id
        end

        tag866list = []
        marc.each_by_tag('866') do |this866|
          tag866list.push(this866) if this866['0'] == mfhd_id
        end

        tag890list = []
        marc.each_by_tag('890') do |this890|
          tag890list.push(this890) if this890['0'] == mfhd_id
        end

        @location_name = tag852['a'] || tag852['b']
        location_code = tag852['b']

        # create_operator_id = xml_node.at_css("mfhd|mfhdData[@name='createOperatorId']").content

        @call_number = parse_call_number(tag852)    # string
        @summary_holdings = parse_summary_holdings(tag866list)  # array
        # @notes_852 = parse_notes_852(tag852)    # array
        # @notes_866 = parse_notes_866(tag866list)    # array
        # combine notes into a single array
        # @public_notes = @notes_852 + @notes_866        # array
        @public_notes = parse_public_notes(tag890list)        # array
        @shelving_title = parse_shelving_title(tag852)  # string

        holdings_tags = ['867', '868',
                         '876',
                         '891', '892', '893', '894', '895']

        holdings_marc = MARC::Record.new()
        marc.each_by_tag(holdings_tags) do |tag|
          holdings_marc.append(tag) if tag['0'] == mfhd_id
        end

        # 867$a
        @supplements = parse_supplements(holdings_marc)    # array
        # 868$a	
        @indexes = parse_indexes(holdings_marc)    # array
        # 892
        @reproduction_note = parse_reproduction_note(holdings_marc)    #string
        # 893
        @urls = parse_urls(holdings_marc)    # array of hashes
        # 891
        @donor_info = parse_donor_info(holdings_marc)  # array of hashes

        @location_note = assign_location_note(location_code)  #string

        # information from item level records
        # item = Item.new(xml_node,@location_name)
        item = Item.new(mfhd_id, holdings_marc, mfhd_status)

        @item_count = item.item_count

        @temp_locations = item.temp_locations
        @item_status = item.item_status

        # flag for services processing (doc_delivery assignment)
        # NEXT-1234: revised logic
        @temp_loc_flag = 'N'
        if @temp_locations.size > 0

          # if all items have temp locations we can't determine doc delivery status (no location codes available in item information) 
          @temp_loc_flag = 'Y' if @temp_locations.length == @item_count
          # special case for single temp location
          if @item_count == 1
            # # temp location begins 'Shelved in' if it is not for a part
            # if @temp_locations.first.match(/^Shelved/)
            #   # remove 'Shelved in' and replace location_name with temp location
            #   @location_name = @temp_locations.first.gsub(/^Shelved in /, '')
            #   @temp_locations.clear
            # end
            # itemLabel will be empty if it is not for a part
            if @temp_locations.first[:itemLabel].blank?
              # replace location_name with temp location, clear temp location
              @location_name = @temp_locations.first[:tempLocation]
              @temp_locations.clear
            end
          end
        end

        # set item status for online items
        if @location_name.match(/^Online/)
          @item_status[:status] = 'online'
          @item_status[:messages].clear
        end

        # information from order/receipt records
        order = Order.new(holdings_marc)

        @current_issues = order.current_issues

        # TODO
        # @orders = order.orders

        # TODO
        # # NEXT-1170
        # # test for approval records without purchase orders (holdomgs with call numbers do not need to be tested)
        # # the second test is in place to make sure no additional processing has occurred
        # if @call_number.empty? && create_operator_id.match("APPR") && @orders.empty?
        #   if [@summary_holdings, @notes, @shelving_title, @supplements, @indexes, @reproduction_note,
        #       @urls, @donor_info, @current_issues].all? { |var| var.empty? }
        #     # treat as pre-order record
        #     @orders << { :status_code => '0', 
        #                   :short_message => 'In the Pre-Order Process', 
        #                   :long_message => 'In the Pre-Order Process. Try Borrow Direct or ILL.' }
        #   end
        # end

        # get format codes from leader
        fmt = marc.leader[6..7]

        # add available services
        @services = determine_services(@location_name, location_code, @temp_loc_flag, @call_number, @item_status, @orders, @bibid, fmt)

      end

      # Collect data from all variables into a hash
      #
      # * *Returns* :
      #   - Hash
      #
      def to_hash
        {
          :bibid => @bibid,
          :holding_id => @holding_id,
          :location_name => @location_name,
          :location_note => @location_note,
          :call_number => @call_number,
          :shelving_title => @shelving_title,
          :summary_holdings => @summary_holdings,
          :supplements => @supplements,
          :indexes => @indexes,
          :public_notes => @public_notes,
          :reproduction_note => @reproduction_note,
          :urls => @urls,
          :donor_info => @donor_info,
          :item_count => @item_count,
          :temp_locations => @temp_locations,
          :item_status => @item_status,
          :services => @services,
          :current_issues => @current_issues,
          :orders => @orders
        }
      end

      private

      # Extract call number
      #
      # * *Args*    :
      #   - +tag852+ -> 852 field node; not repeatable
      # * *Returns* :
      #   - Call number string
      #
      def parse_call_number(tag852)

        g = tag852.subfields.collect {|s| s.value if s.code == 'g'}
        h = tag852.subfields.collect {|s| s.value if s.code == 'h'}
        i = tag852.subfields.collect {|s| s.value if s.code == 'i'}
        k = tag852.subfields.collect {|s| s.value if s.code == 'k'}
        m = tag852.subfields.collect {|s| s.value if s.code == 'm'}

        # g = tag852.css("slim|subfield[@code='g']").collect { |subfield| subfield.content }
        # h = tag852.css("slim|subfield[@code='h']").collect { |subfield| subfield.content }
        # i = tag852.css("slim|subfield[@code='i']").collect { |subfield| subfield.content }
        # k = tag852.css("slim|subfield[@code='k']").collect { |subfield| subfield.content }
        # m = tag852.css("slim|subfield[@code='m']").collect { |subfield| subfield.content }

        # subfields need to be output in this order even though they may not appear in this order
        [k,g,h,i,m].flatten.join(' ').strip

      end

      # Extract summary holdings from 866 field
      #
      # * *Args*    :
      #   - +tag866list+ -> Array of 866 field nodes, 
      # * *Returns* :
      #   - Array of summary holdings statements
      #   - Empty array if there are no summary holdings
      #
      def parse_summary_holdings(tag866list)
        return [] unless tag866list && tag866list.size > 0

        summary = tag866list.collect { |tag866|
          tag866.subfields.select {|s| s.code == 'a'  && ! s.value.empty?}.collect{|s| s.value }
        }.flatten

# raise
        # summary = tag866.subfields.collect {|s| s.value if s.code == 'a'}
        # summary.compact.collect { |subfield| subfield.strip }
        # raise
      end

      def parse_public_notes(tag890list)
        return [] unless tag890list && tag890list.size > 0

        public_notes = tag890list.collect { |tag890|
          tag890.subfields.select {|s| s.code == 'a'  && ! s.value.empty?}.collect{|s| s.value }
        }.flatten

      end

      # # Extract public notes from 852 field, subfield z
      # #
      # # * *Args*    :
      # #   - +tag852+ -> 852 field node; not repeatable
      # # * *Returns* :
      # #   - Array of note statements
      # #   - Empty array if there are no notes
      # #
      # def parse_notes_852(tag852)
      #   return [] unless tag852 && tag852['z']
      # 
      #   notes = tag852.subfields.collect {|s| s.value if s.code == 'z'}
      #   notes.compact.collect { |subfield| subfield.strip }
      # 
      #   # subz = tag852.css("slim|subfield[@code='z']")
      #   # # there can be multiple z's
      #   # subz.collect { |subfield| subfield.content }
      # end
      # 
      # # Extract public notes from 866 fields, subfield z
      # #
      # # * *Args*    :
      # #   - +tag866+ -> 866 field node; repeatable
      # # * *Returns* :
      # #   - Array of note statements
      # #   - Empty array if there are no notes
      # #
      # def parse_notes_866(tag866list)
      #   return [] unless tag866list && tag866list.size > 0
      # 
      #   summary = tag866list.collect { |tag866|
      #     tag866.subfields.select {|s| s.code == 'z'  && ! s.value.empty?}.collect{|s| s.value }
      #   }.flatten
      # 
      #   # return [] unless tag866 && tag866['z']
      #   # 
      #   # notes = tag866.subfields.collect {|s| s.value if s.code == 'z'}
      #   # notes.compact.collect { |subfield| subfield.strip }
      # 
      #   # return [] unless tag866
      #   # 
      #   # notes = tag866.collect do |field|
      #   #   field.at_css("slim|subfield[@code='z']")
      #   # end
      #   # 
      #   # notes.compact.collect { |subfield| subfield.content }
      # 
      # end

      # Extract shelving title
      #
      # * *Args*    :
      #   - +tag852+ -> 852 field node; not repeatable
      # * *Returns* :
      #   - Shelving title string
      #
      def parse_shelving_title(tag852)
        return '' unless tag852 && tag852['l']

        return tag852['l'].strip

        # subl = tag852.at_css("slim|subfield[@code='l']")
        # subl ? subl.content : ''
      end

      # Extract supplement holdings from field 867
      #
      # * *Args*    :
      #   - +marc+ -> mfhd:marcRecord node
      # * *Returns* :
      #   - Array of supplement holdings statements
      #   - Empty array if there are no summary holdings
      #      
      def parse_supplements(marc)
        tag867 = marc['867']
        return [] unless tag867

        supplements = []

        marc.each_by_tag('867') do |t867|
          supplements.push( t867.subfields.collect {|s| s.value if ['a', 'z'].include? s.code}.join(' ').strip )
        end
        # 
        # tag867.each do |field|
        #   subs = field.css("slim|subfield").collect { |subfield| subfield.content if subfield.attr("code").match(/[az]/)}
        #     supplements << subs.join(" ").strip unless subs.empty?
        # end

        supplements

      end

      # Extract index holdings from field 868
      #
      # * *Args*    :
      #   - +marc+ -> mfhd:marcRecord node
      # * *Returns* :
      #   - Array of index holdings statements
      #   - Empty array if there are no summary holdings
      #      
      def parse_indexes(marc)
        tag868 = marc['868']
        return [] unless tag868

        indexes = []

        marc.each_by_tag('868') do |t868|
          indexes.push( t868.subfields.collect {|s| s.value if s.code == 'a'}.join(' ').strip )
        end

        indexes


        # tag868 = marc.css("slim|datafield[@tag='868']")
        # 
        # return [] unless tag868
        # 
        # indexes = []
        # tag868.each do |field|
        #   subs = field.css("slim|subfield").collect { |subfield| subfield.content if subfield.attr("code").match(/[az]/)}
        #     indexes << subs.join(" ").strip unless subs.empty?
        # end
        # 
        # indexes

      end

      # Extract reproduction note from field 843
      #
      # * *Args*    :
      #   - +marc+ -> mfhd:marcRecord node
      # * *Returns* :
      #   - Reproduction note string
      #      
      def parse_reproduction_note(marc)
        tag892 = marc['892']
        return '' unless tag892

        # collect subfields in input order; only ouput certain subfields
        # tag843.css("slim|subfield").collect { |subfield| subfield.content if subfield.attr("code").match(/[abcdefmn3]/)}.join(' ')

        tag892.subfields.collect {|s| s.value if 'abcdefmn3'.include? s.code}.join(' ').strip

      end

      # Extract URLs from 856 fields in the marc holdings record
      #
      # * *Args*    :
      #   - +marc+ -> mfhd:marcRecord node
      # * *Returns* :
      #   - Array of hashes for urls
      #     { :url => url, :link_text => link text }
      #   - Empty array if there are no urls in the holdings record
      # Note: there may be urls in the bib record.
      #
      def parse_urls(marc)
        tag893 = marc['893']
        return [] unless tag893

        urls = []
        marc.each_by_tag('893') do |t893|
          ind1 = t893.indicator1
          ind2 = t893.indicator2

          subu = t893['u']
          subz = t893['z']
          sub3 = t893['3']

          if subu
            url = subu
            link_text = [sub3, subz].compact.collect { |subfield| subfield.value }.join(' ')
            link_text = url if link_text.empty?
            urls << {ind1: ind1, ind2: ind2, url: url, link_text: link_text}
          end
        end
        urls

        # # tag856 = marc.css("slim|datafield[@tag='856']")
        # # 
        # # return [] unless tag856
        # 
        # urls = []
        # 
        # tag856.each do |field|
        # 
        #   ind1 = field.attr("ind1")
        #   ind2 = field.attr("ind2")
        # 
        #   subu = field.at_css("slim|subfield[@code='u']")
        #   subz = field.at_css("slim|subfield[@code='z']")
        #   sub3 = field.at_css("slim|subfield[@code='3']")
        # 
        #   # only process if there is a url
        #   if subu
        # 
        #     url = subu.content
        # 
        #     link_text = [sub3, subz].compact.collect { |subfield| subfield.content }
        # 
        #     if link_text.empty?
        #       link_text << url
        #     end
        # 
        #     urls << { :ind1 => ind1, :ind2 => ind2, :url => url, :link_text => link_text.join(' ') }
        # 
        #   end
        # 
        #   # # only process idicators 40
        #   # if field.attr("ind1") == '4' and field.attr("ind2") == '0'
        #   #   
        #   #   subu = field.at_css("slim|subfield[@code='u']")
        #   #   subz = field.at_css("slim|subfield[@code='z']")
        #   #   sub3 = field.at_css("slim|subfield[@code='3']")
        #   #  
        #   #   # only process if there is a url
        #   #   if subu
        #   #   
        #   #     url = subu.content
        #   #     
        #   #     link_text = [sub3, subz].compact.collect { |subfield| subfield.content }
        #   # 
        #   #     if link_text.empty?
        #   #       link_text << url
        #   #     end
        #   #     
        #   #     urls << { :url => url, :link_text => link_text.join(' ') }
        #   #   
        #   #   end
        #   # end
        # end
        # 
        # urls

      end

      # Extract donor note & code from field 541
      #
      # * *Args*    :
      #   - +marc+ -> mfhd:marcRecord node
      # * *Returns* :
      #   - Array of hashes for donor information
      #     { :message => message, :code => code }
      #   - Empty array if there are no donor notes
      #      
      def parse_donor_info(marc)
        tag891 = marc['891']
        return [] unless tag891

        donor_info = []
        marc.each_by_tag('891') do |t891|
          next unless t891.indicator1 == '1'

          # collect subfields in input order; only ouput certain subfields
          # do not include subfield c and 3 in brief message (use with gift icon)
          message = t891.subfields.collect {|s| s.value if 'acd3'.include? s.code}.compact.join(' ').strip
          message_brief = t891.subfields.collect {|s| s.value if 'ad'.include? s.code}.compact.join(' ').strip
          sube = t891['e']
          code = ''
          code = sube.strip if sube
          # get the name coded after 'plate:'
          name = ''
          name = $1.strip if code.downcase.match(/^plate:(.+)/)
          # use name to see if there is a url to a donor page or a special text
          url = ''
          unless name.empty?
            entry = DONOR_INFO[name]
            unless entry.nil?
              url = entry['url']
              message_brief = entry['txt'] unless entry['txt'].empty?
            end
          end
          donor_info << { message: message, message_brief: message_brief, code: code, url: url }
        end

        donor_info


        # tag541 = marc.css("slim|datafield[@tag='541']")
        # 
        # return [] unless tag541
        # 
        # donor_info = []
        # 
        # tag541.each do |field|
        # 
        #   # only process if first idicator 1
        #   if field.attr("ind1") == '1'
        # 
        #     # collect subfields in input order; only ouput certain subfields
        #     # do not include subfield c and 3 in brief message (use with gift icon)
        #     message = field.css("slim|subfield").collect { |subfield| subfield.content if subfield.attr("code").match(/[acd3]/)}.compact.join(' ').strip
        #     message_brief = field.css("slim|subfield").collect { |subfield| subfield.content if subfield.attr("code").match(/[ad]/)}.compact.join(' ').strip
        #     sube = field.at_css("slim|subfield[@code='e']")
        #     code = ''
        #     code = sube.content.strip if sube
        #     # get the name coded after 'plate:'
        #     name = ''
        #     name = $1.strip if code.downcase.match(/^plate:(.+)/)
        #     # use name to see if there is a url to a donor page or a special text
        #     url = ''
        #     unless name.empty?
        #       entry = DONOR_INFO[name]
        #       unless entry.nil?
        #         url = entry['url']
        #         message_brief = entry['txt'] unless entry['txt'].empty?
        #       end
        #     end
        #     donor_info << { :message => message, :message_brief => message_brief, :code => code, :url => url }
        #   end
        # 
        # end
        # 
        # donor_info

      end

      def assign_location_note(location_code)
        location_note = ''

        # Avery Art Properties (NEXT-1318)
        if location_code == 'avap'
          location_note = 'By appointment only. See the <a href="http://library.columbia.edu/locations/avery/art-properties.html" target="_blank">Avery Art Properties webpage</a>'
          return location_note
        end
        # Avery Classics
        if ['avr','avr,cage','avr,rrm','avr,stor','far','far,cage','far,rrm','far,stor','off,avr','off,far'].include?(location_code)
          location_note = 'By appointment only. See the <a href="http://library.columbia.edu/locations/avery/classics.html" target="_blank">Avery Classics Collection webpage</a>'
          return location_note
        end
        # Avery Drawings & Archives (NEXT-1318)
        if ['avda','ava','off,avda'].include?(location_code)
          location_note = 'By appointment only. See the <a href="http://library.columbia.edu/locations/avery/da.html" target="_blank">Avery Drawings & Archives webpage</a>'
          return location_note
        end
        # Barnard Archives
        if ['bar,bda','bar,spec','bara'].include?(location_code)
          location_note = 'In off-site storage - Request from <a href="http://archives.barnard.edu/about-us/contact-us">Barnard Archives</a>'
          return location_note
        end
        # Burke
        if ['uts,arc','uts,essxx1','uts,essxx2','uts,essxx3','uts,gil','uts,mac','uts,macxfp','uts,macxxf','uts,macxxp',
            'uts,map','uts,mrldr','uts,mrldxf','uts,mrlor','uts,mrloxf','uts,mrls','uts,mrlxxp','uts,mss','uts,perr','uts,perrxf',
            'uts,reled','uts,tms','uts,twr','uts,twrxxf','uts,unnr','uts,unnrxf','uts,unnrxp'].include?(location_code)
          location_note = 'By appointment only. See the <a href="http://library.columbia.edu/locations/burke/access_circulation/special-collections-access.html" target="_blank">Burke Library special collections page</a>'
          return location_note
        end

        location_note
      end


      def determine_services(location_name, location_code, temp_loc_flag, call_number, item_status, orders, bibid, fmt)
        services = []

        # NEXT-1229 - make this the first test
        # special collections request service [only service available for items from these locations]
        if ['rbx','off,rbx','rbms','off,rbms','rbi','uacl','off,uacl','clm','dic','dic4off','gax','oral',
          'rbx4off','off,dic','off,oral'].include?(location_code)
          return ['spec_coll']
        end

        # Orders such as "Pre-Order", "On-Order", etc.  
        # List of available services per order status hardcoded into yml config file.
        if orders.present?
          orders.each do |order|
            order_config = ORDER_STATUS_CODES[order[:status_code]]
            raise "Status code not found in config/order_status_codes.yml" unless order_config
            services << order_config['services'] unless order_config['services'].nil?
          end
          return services.flatten.uniq
        end

        # Scan for things like "Recall", "Hold", etc.
        services << scan_message(location_name)

        messages = item_status[:messages]

        case item_status[:status]
        when 'online'
        when 'none'
          services << 'in_process' if call_number.match(/in process/i)
        when 'available'
          services << process_for_services(location_name,location_code,temp_loc_flag,bibid,messages)
        when 'some_available'
          services << process_for_services(location_name,location_code,temp_loc_flag,bibid,messages)
        when 'not_available'
          services << scan_messages(messages) if messages.present?
        else
        end

        # only provide borrow direct request for printed books and scores
        unless fmt == 'am' || fmt == 'cm'
          services.delete('borrow_direct')
        end

        # return the cleaned up list
        services = services.flatten.uniq
      end


      def process_for_services(location_name,location_code,temp_loc_flag,bibid,messages)
        services = []

        # offsite
        # if location_name.match(/^Offsite/) &&
        #     HTTPClient.new.get_content("http://www.columbia.edu/cgi-bin/cul/lookupNBX?" + bibid) == "1"
        if location_name.match(/^Offsite/) && OFFSITE_CONFIG['offsite_locations'].include?(location_code)
          services << 'offsite'
          # services << 'offsite_valet'

        # precat
        elsif location_name.match(/^Precat/)
           services << 'precat'

        # doc delivery
        elsif ['ave', 'avelc', 'bar', 'bar,mil', 'bus', 'eal', 'eax', 'eng',
               'fax', 'faxlc', 'glg', 'glx', 'glxn', 'gsc', 'jou',
               'leh', 'leh,bdis', 'mat', 'mil', 'mus', 'sci', 'swx',
               'uts', 'uts,per', 'uts,unn', 'war' ].include?(location_code) &&
               temp_loc_flag == 'N'
          services << 'doc_delivery'
        end

        services << scan_messages(messages) if messages.present?

        services
      end


      def scan_messages(messages)
        services = []
        messages.each do |message|
          # status patrons
          if message[:status_code] == 'sp'
            services << scan_message(message[:long_message])
          else
            status_code_config = ITEM_STATUS_CODES[message[:status_code]]
            raise "Status code not found in config/order_status_codes.yml" unless status_code_config
            services << status_code_config['services'] unless status_code_config['services'].nil?
          end
        end
        services
      end

      # Scan item message string for things like "Recall", "Hold", etc.
      def scan_message(message)
        out = []
        out << 'recall_hold'    if message =~ /Recall/i
        out << 'recall_hold'    if message =~ /hold /
        out << 'borrow_direct'  if message =~ /Borrow/
        out << 'ill'            if message =~ /ILL/
        out << 'in_process'     if message =~ /In Process/
        # ReCAP Partners
        out << 'offsite_valet'  if message =~ /scsb/
        out
      end

    end

  end
end
