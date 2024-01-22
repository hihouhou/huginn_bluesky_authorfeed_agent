module Agents
  class BlueskyAuthorfeedAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The Bluesky Authorfeed Agent checks user's feed.

      `debug` is used for verbose mode.

      `handle` is mandatory for authentication.

      `limit` is needed to limit the number of results.

      `user` is the wanted user you want to check.

      `app_password` is mandatory for authentication.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "post": {
              "uri": "at://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX/app.bsky.feed.post/XXXXXXXXXXXXX",
              "cid": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
              "author": {
                "did": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
                "handle": "hihouhou.bsky.social",
                "viewer": {
                  "muted": false,
                  "blockedBy": false,
                  "followedBy": "at://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX/app.bsky.graph.follow/XXXXXXXXXXXXX"
                },
                "labels": [

                ]
              },
              "record": {
                "text": "test for authorfeed agent (huginn)",
                "$type": "app.bsky.feed.post",
                "langs": [
                  "fr"
                ],
                "createdAt": "2023-12-15T20:21:50.150Z"
              },
              "replyCount": 1,
              "repostCount": 0,
              "likeCount": 0,
              "indexedAt": "2023-12-15T20:21:50.150Z",
              "viewer": {
              },
              "labels": [

              ]
            }
          }
    MD

    def default_options
      {
        'user' => '',
        'debug' => 'false',
        'handle' => '',
        'limit' => '10',
        'app_password' => '',
        'expected_receive_period_in_days' => '2',
      }
    end

    form_configurable :user, type: :string
    form_configurable :debug, type: :boolean
    form_configurable :app_password, type: :string
    form_configurable :handle, type: :string
    form_configurable :limit, type: :string
    form_configurable :expected_receive_period_in_days, type: :string
    def validate_options
      unless options['user'].present?
        errors.add(:base, "user is a required field")
      end

      unless options['app_password'].present?
        errors.add(:base, "app_password is a required field")
      end

      unless options['handle'].present?
        errors.add(:base, "handle is a required field")
      end

      unless options['limit'].present?
        errors.add(:base, "limit is a required field")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end


    def check
      get_feed()
    end

    private

    def log_curl_output(code,body)

      log "request status : #{code}"

      if interpolated['debug'] == 'true'
        log "body"
        log body
      end

    end

    def generate_did(user)
      uri = URI.parse("https://bsky.social/xrpc/com.atproto.identity.resolveHandle")
      params = { :handle => user }
      uri.query = URI.encode_www_form(params)
      response = Net::HTTP.get_response(uri)
    
      log_curl_output(response.code,response.body)
    
      return JSON.parse(response.body)['did']
    end
    
    def generate_api_key(did)
      uri = URI.parse("https://bsky.social/xrpc/com.atproto.server.createSession")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request.body = JSON.dump({
        "identifier" => did,
        "password" => interpolated['app_password']
      })
    
      req_options = {
        use_ssl: uri.scheme == "https",
      }
    
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    
      log_curl_output(response.code,response.body)
    
      return JSON.parse(response.body)['accessJwt']
    end
    
    def get_feed()

      did = generate_did(interpolated['handle'])
      uri = URI.parse("https://bsky.social/xrpc/app.bsky.feed.getAuthorFeed?actor=#{generate_did(interpolated['user'])}&limit=#{interpolated['limit']}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{generate_api_key(did)}"
    
      req_options = {
        use_ssl: uri.scheme == "https",
      }
    
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    
      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)

      if payload != memory['last_status']
        payload['feed'].each do |feed|        
          found = false
          if !memory['last_status'].nil? and memory['last_status']['feed'].present?
            last_status = memory['last_status']
            if interpolated['debug'] == 'true'
              log "feed"
              log feed
            end
            last_status["feed"].each do |feedbis|
              if feed == feedbis or feed['post']['uri'] == feedbis['post']['uri']
                found = true
                if interpolated['debug'] == 'true'
                  log "found is #{found}"
                end
              end
            end
          end
          if found == false
            create_event payload: feed
          else
            if interpolated['debug'] == 'true'
              log "found is #{found}"
            end
          end
        end
        memory['last_status'] = payload
      else
        if interpolated['debug'] == 'true'
          log "no diff"
        end
      end
    end
  end
end
