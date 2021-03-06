module Voyager
  module Holdings
    class Collection
      attr_reader :records, :xml


      def initialize(document, circ_status)
        raise "Voyager::Holdings::Collection got nil/empty document" unless document
        # raise "Voyager::Holdings::Collection got nil/empty circ_status" unless circ_status

        circ_status ||= {}
        document_status = circ_status[document.id] || {}
        document_marc = document.to_marc

        # collect mfhd records
        @records = []
        document_marc.each_by_tag('852') do |t852|
          # Sequence - MFHD ID used to gather all associated fields
          mfhd_id = t852['0']
          mfhd_status = document_status[mfhd_id] || {}
          # Rails.logger.debug "parse_marc:  mfhd_id=[#{mfhd_id}]"
          @records << Record.new(mfhd_id, document_marc, mfhd_status)
        end

        adjust_services(@records) if @records.length > 1

      end

      # Generate output hash from Record class instances
      def to_hash(options = {})
        options.reverse_merge!(:output_type => :raw, :content_type => :full, :message_type => :long_message)

        # :output_type --> :raw (default) | :condensed
        # 
        # if :output_type == :condensed
        #   :content_type --> :brief | :full (default)
        #     :brief  -->  basic elements: currently location_name, call_number, overall location status, services
        #     :full   -->  all elements
        #   if :content_type == :full
        #     :message_type --> :short_message | :long_message (default)
        #   

        raise ":output_type not defined" unless options[:output_type] == :raw || options[:output_type] == :condensed
        raise ":content_type not defined" unless options[:content_type] == :full || options[:content_type] == :brief
        raise ":message_type not defined" unless options[:message_type] == :long_message || options[:message_type] == :short_message

        output = {}

        case options[:output_type]
        when :raw
          output[:records] = @records.collect { |rec| rec.to_hash }
        when :condensed
          # convert @records into a holdings hash
          holdings = @records.collect { |rec| rec.to_hash }
          case options[:content_type]
          when :full
            output[:condensed_holdings_full] = condense_holdings(holdings,options)
          when :brief
            output[:condensed_holdings_brief] = condense_holdings(holdings,options)
          end
        end

        output.with_indifferent_access
      end

      private

      # # Add searchable namespaces to xml object
      # def add_xml_namespaces(xml)
      #   xml.root.add_namespace_definition("hol", "http://www.endinfosys.com/Voyager/holdings")
      #   xml.root.add_namespace_definition("mfhd", "http://www.endinfosys.com/Voyager/mfhd")
      #   xml.root.add_namespace_definition("item", "http://www.endinfosys.com/Voyager/item")
      #   xml.root.add_namespace_definition("slim", "http://www.loc.gov/MARC21/slim")
      #   return xml
      # end

      # # Collect Record class instances for each mfhd:mfhdRecord node in xml record objext
      # def parse_xml
      #   # First, look for any service messages - raise them as an error
      #   if first_ser_message = @xml.at_xpath('//ser:messages/ser:message')
      #     # just throw as Rails default StandardError, with details in the message
      #     raise "#{first_ser_message.attr('errorCode')} #{first_ser_message.content}"
      #   end
      # 
      #   leader = @xml.at_css("hol|bibRecord>hol|marcRecord>slim|leader").content
      #   @records = @xml.css("hol|mfhdCollection>mfhd|mfhdRecord").collect do |record_node|
      #     Record.new(record_node,leader)
      #   end
      #   adjust_services(@records) if @records.length > 1
      # end

      # def parse_marc(marc)
      #   # Rails.logger.debug "parse_marc() marc:\n#{marc.inspect}\n"
      #   # collect mfhd records
      #   @records = []
      #   marc.each_by_tag('852') do |t852|
      #     # Sequence - MFHD ID used to gather all associated fields
      #     mfhd_id = t852['0']
      #     Rails.logger.debug "parse_marc:  mfhd_id=[#{mfhd_id}]"
      #     @records << Record.new(mfhd_id, marc)
      #   end
      # 
      # end


      # For records with multiple holdings, based on the overall content, adjust as follows:
      # -- remove document delivery options if there is an available offsite copy
      # -- remove borrowdirect and ill options if there is an available non-reserve, circulating copy
      def adjust_services(records)

        # set flags
        offsite_copy = "N"
        available_copy = "N"
        records.each do |record|
          offsite_copy = "Y" if record.services.include?('offsite')
          if record.item_status[:status] == 'available'
            available_copy = "Y" unless record.location_name.match(/Reserve|Non\-Circ/)
          end
        end

        # adjust services
        records.each do |record|
          record.services.delete('doc_delivery') if offsite_copy == "Y"
          record.services.delete('borrow_direct') if available_copy == "Y"
          record.services.delete('ill') if available_copy == "Y"
        end

      end

      def condense_holdings(holdings,options)
        # processing varies depending on complexity
        complexity = determine_complexity(holdings)
        process_holdings(holdings, complexity, options)
      end

      def determine_complexity(holdings)
        # holdings are complex if anything other than item_status has a value
        complexity = :simple

        holdings.each do |holding|
          if [:summary_holdings, :supplements, :indexes, :public_notes,
              :reproduction_note, :current_issues,
              :temp_locations,
              :orders,
              :donor_info, :urls].any? { |key| holding[key].present?}
            complexity = :complex
          end
        end

        complexity
      end

      def process_holdings(holdings,complexity,options)
        entries = []
        holdings.each do |holding|
          # test for location and call number
          entry = entries.find { |this_entry| this_entry[:location_name] == holding[:location_name] &&
            this_entry[:call_number] == holding[:call_number] }

          unless entry
            entry = {
              :location_name => holding[:location_name],
              :location_note => holding[:location_note],
              :call_number => holding[:call_number],
              :status => '',
              :holding_id => [],
              :copies => [],
              :services => []
            }
            entry[:copies] << {:items => {}} if complexity == :simple
            entries << entry
          end

          # add holding_id
          entry[:holding_id] << holding[:holding_id]

          # for simple holdings put consolidated status information in the first copy
          if complexity == :simple
            item_status = holding[:item_status]
            messages = item_status[:messages]
            messages.each do |message|
              text = message[options[:message_type]]
              if entry[:copies].first[:items].has_key?(text)
                entry[:copies].first[:items][text][:count] += 1
              else
                entry[:copies].first[:items][text] = {
                  :status => item_status[:status],
                  :count => 1
                }
              end
            end
          # for complex holdings create hash of elements for each copy and add to entry :copies array
          else
            out = {}
            # process status messages
            item_status = holding[:item_status]
            messages = item_status[:messages]
            out[:items] = {}
            messages.each do |message|
              text = message[options[:message_type]]
              if out[:items].has_key?(text)
                out[:items][text][:count] += 1
              else
                out[:items][text] = {
                  :status => item_status[:status],
                  :count => 1
                }
              end
            end
            # add other elements to :copies array
            [:current_issues, :donor_info, :indexes, :public_notes, :orders, :reproduction_note, :supplements,
              :summary_holdings, :temp_locations, :urls].each { |type| add_holdings_elements(out,holding,type,options[:message_type]) }

            entry[:copies] << out

          end

          entry[:services] << holding[:services]

        end

        # get overall status of each location entry
        entries.each { |entry| determine_overall_status(entry) }

        # condense services list
        entries.each { |entry| entry[:services] = entry[:services].flatten.uniq }

        output_condensed_holdings(entries,options[:content_type])
      end


      def add_holdings_elements(out,holding,type,message_type)
        case type
        when :current_issues
          out[type] = "Current Issues: " + holding[type].join(' -- ') unless holding[type].empty?
        when :donor_info
          unless holding[type].empty?
            # for text display as note
            messages = holding[type].each.collect { |info| info[:message] }
            out[type] = "Donor: " + messages.uniq.join(' -- ')
            # for display in conjunction with the Gift icon
            # this is set up to dedup but so far there have only been single donor info entries per holding
            out[:donor_info_icon] = []
            message_list = []
            holding[type].each do |info|
              unless message_list.include?(info[:message_brief])
                out[:donor_info_icon] << { :message => info[:message_brief], :url => info[:url] }
                message_list << info[:message_brief]
              end
            end
          end
        when :indexes
          out[type] = "Indexes: " + holding[type].join(' -- ') unless holding[type].empty?
        when :public_notes
          out[type] = "Notes: " + holding[type].join(' -- ') unless holding[type].empty?
        # TODO
        # when :orders
        #   unless holding[type].empty?
        #      messages = holding[type].each.collect { |message| message[message_type] }
        #      out[type] = "Order Information: " + messages.join(' -- ')
        #   end
        when :reproduction_note
          out[type] = holding[type] unless holding[type].empty?
        when :supplements
          out[type] = "Supplements: " + holding[type].join(' -- ') unless holding[type].empty?
        when :summary_holdings
          out[type] = "Library has: " + holding[type].join(' -- ') unless holding[type].empty?
        when :temp_locations
          out[type] = holding[type] unless holding[type].empty?
        when :urls
          out[type] = holding[type] unless holding[type].empty?
        else
        end

      end

      def determine_overall_status(entry)

        a = 0   # available
        s = 0   # some available
        n = 0   # not available

        status = ''

        entry[:copies].each do |copy|
          copy[:items].each_pair do |message,details|
            a = 1 if details[:status] == 'available'
            s = 2 if details[:status] == 'some_available'
            n = 4 if details[:status] == 'not_available'
          end
        end

        #               |  some           |  not
        # available (1) |  available (2)  |  available (4)    total (a+s+n)
        # -----------------------------------------------------------------
        #     Y               Y                 Y               7
        #     Y               Y                 N               3
        #     Y               N                 Y               5
        #     Y               N                 N               1
        #     N               Y                 Y               6
        #     N               Y                 N               2
        #     N               N                 Y               4
        #     N               N                 N               0
        #
        # :available is returned if all items are available (1).
        # :not_available is returned if everything is unavailable (4).
        # :none is returned if there is no status (0).
        # otherwise :some_available is returned:
        # All status are checked; as long as something is available, even if
        # there are some items check out, :some_available is returned.
        #

        case a + s + n
        when 0
          status = 'none'
          status = 'online' if entry[:location_name].match(/^Online/)
        when 1
          status = 'available'
        when 4
          status = 'not_available'
        else
          status = 'some_available'
        end

        entry[:status] = status

      end

      def output_condensed_holdings(entries,type)

        case type
        when :full
          entries
        when :brief
          entries.collect do |entry|
            { :holding_id => entry[:holding_id],
              :location_name => entry[:location_name],
              :call_number => entry[:call_number],
              :status => entry[:status],
              :services => entry[:services] }
          end
        end

      end

    end
  end
end
