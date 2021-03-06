require 'rack'

module NewRelic::Rack
  class BrowserMonitoring

    def initialize(app, options = {})
      @app = app
    end

    # method required by Rack interface
    def call(env)
      result = @app.call(env)   # [status, headers, response]

      if (NewRelic::Agent.browser_timing_header != "") && should_instrument?(result[0], result[1])
        response_string = autoinstrument_source(result[2], result[1])

        if response_string
          response = Rack::Response.new(response_string, result[0], result[1])
          response.finish
        else
          result
        end
      else
        result
      end
    end

    def should_instrument?(status, headers)
      status == 200 && headers["Content-Type"] && headers["Content-Type"].include?("text/html") &&
        !headers['Content-Disposition'].to_s.include?('attachment')
    end

    def autoinstrument_source(response, headers)
      source = nil
      response.each {|fragment| source ? (source << fragment.to_s) : (source = fragment.to_s)}
      return nil unless source


      # Only scan the first 50k (roughly) then give up.
      beginning_of_source = source[0..50_000]
      # Don't scan for body close unless we find body start
      if (body_start = beginning_of_source.index("<body")) && (body_close = source.rindex("</body>"))

        footer = NewRelic::Agent.browser_timing_footer
        header = NewRelic::Agent.browser_timing_header

        head_pos = if beginning_of_source.include?('X-UA-Compatible')
          # put at end of header if UA-Compatible meta tag found
          beginning_of_source.index("</head>")
       elsif head_open = beginning_of_source.index("<head")
          # put at the beginning of the header
          beginning_of_source.index(">", head_open) + 1
        end
        # otherwise put the header right above body start
        head_pos ||= body_start

        # check that head_pos is less than body close.  If it's not something
        # is really weird and we should punt.
        if head_pos < body_close
          # rebuild the source
          source = source[0..(head_pos-1)] <<
            header <<
            source[head_pos..(body_close-1)] <<
            footer <<
            source[body_close..-1]
        end
      end
      headers['Content-Length'] = source.length.to_s if headers['Content-Length']
      source
    end
  end

end
