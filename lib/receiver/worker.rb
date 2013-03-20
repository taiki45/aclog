require "time"

module EM
  class Connection
    def send_object(data)
      send_data(data.to_msgpack)
    end
  end
end

class Receiver::Worker < DaemonSpawn::Base
  class DBProxyServer < EM::Connection
    @@wq = EM::WorkQueue::WorkQueue.new do |arg|
      arg.call
    end
    @@wq.start

    def send_account_all
      Account.where("id % ? = ?", Settings.worker_count, @worker_number).each do |account|
        puts "Sent #{account.id}/#{account.user_id}"
        send_account(account)
      end
    end

    def send_account(account)
      out = {:type => "account",
             :id => account.id,
             :oauth_token => account.oauth_token,
             :oauth_token_secret => account.oauth_token_secret,
             :user_id => account.user_id}
      send_object(out)
    end

    def initialize
      $connections ||= {}
      @worker_number = nil
      @pac = MessagePack::Unpacker.new
    end

    def post_init
      # なにもしない。クライアントが
    end

    def unbind
      $connections.delete_if{|k, v| v == self}
      $logger.info("Connection closed: #{@worker_number}")
    end

    def receive_data(data)
      @pac.feed_each(data) do |msg|
        unless msg["type"]
          $logger.error("???: #{msg}")
          send_object({:type => "fatal", :message => "Unknown data"})
          close_connection_after_writing
          return
        end

        if msg["type"] != "init" && !@authorized
          $logger.error("Not authorized client: #{msg}")
          send_object({:type => "fatal", :message => "You aren't authorized"})
          close_connection_after_writing
          return
        end

        case msg["type"]
        when "init"
          receive_init(msg)
        when "unauthorized"
          receive_unauthorized(msg)
        when "user"
          receive_user(msg)
        when "tweet"
          receive_tweet(msg)
        when "favorite"
          receive_favorite(msg)
        when "retweet"
          receive_retweet(msg)
        when "delete"
          receive_delete(msg)
        when "quit"
          receive_quit(msg)
        else
          $logger.warn("Unknown message type: #{msg["type"]}")
          send_object({:type => "error", :message => "Unknown message type: #{msg["type"]}"})
        end
      end
    end

    def receive_init(msg)
      secret_key = msg["secret_key"]
      worker_number = msg["worker_number"]
      unless secret_key == Settings.secret_key
        $logger.error("Invalid secret_key: #{secret_key}")
        send_object({:type => "fatal", :message => "Invalid secret_key"})
        close_connection_after_writing
        return
      end
      $connections[worker_number] = self
      @worker_number = worker_number
      @authorized = true
      $logger.info("Connected: #{worker_number}")
      send_object({:type => "ok", :message => "Connected"})
      send_account_all
    end

    def receive_unauthorized(msg)
      $logger.warn("Unauthorized: #{msg["user_id"]}")
      # unregister
    end

    def receive_user(msg)
      @@wq.push -> do
        $logger.debug("Received User")
        rec = User.find_or_initialize_by(:id => msg["id"])
        rec.screen_name = msg["screen_name"]
        rec.name = msg["name"]
        rec.profile_image_url = msg["profile_image_url"]
        rec.save! if rec.changed?
      end
    end

    def receive_tweet(msg)
      @@wq.push -> do
        $logger.debug("Received Tweet")
        begin
          Tweet.create!(:id => msg["id"],
                        :text => msg["text"],
                        :source => msg["source"],
                        :tweeted_at => Time.parse(msg["tweeted_at"]),
                        :user_id => msg["user_id"])
          $logger.debug("Saved Tweet")
        rescue ActiveRecord::RecordNotUnique
          $logger.info("Can't Save Tweet: Duplicate")
        end
      end
    end

    def receive_favorite(msg)
      @@wq.push -> do
        $logger.debug("Received Favorite")
        begin
          Favorite.create!(:tweet_id => msg["tweet_id"],
                           :user_id => msg["user_id"])
          $logger.debug("Saved Favorite")
        rescue ActiveRecord::RecordNotUnique
          $logger.info("Can't Save Tweet: Duplicate")
        end
      end
    end

    def receive_retweet(msg)
      @@wq.push -> do
        $logger.debug("Received Retweet")
        begin
          Retweet.create!(:id => msg["id"],
                          :tweet_id => msg["tweet_id"],
                          :user_id => msg["user_id"])
          $logger.debug("Saved Retweet")
        rescue ActiveRecord::RecordNotUnique
          $logger.info("Can't Save Retweet: Duplicate")
        end
      end
    end

    def receive_delete(msg)
      @@wq.push -> do
        if msg["id"]
          Tweet.where(:id => msg["id"]).destroy_all
          Retweet.where(:id => msg["id"]).destroy_all
        elsif msg["tweet_id"]
          Favorite
            .where("tweet_id = #{msg["tweet_id"]} AND user_id = #{msg["user_id"]}")
            .destroy_all
        end
      end
    end

    def receive_quit(msg)
      $logger.warn("Quit: #{@worker_number}")
      send_data({:type => "ok", :message => "Bye"})
      close_connection_after_writing
    end
  end

  class RegisterServer < EM::Connection
    def initialize
      @pac = MessagePack::Unpacker.new
    end

    def post_init
    end

    def receive_data(data)
      @pac.feed_each(data) do |msg|
        p msg
        unless msg["type"]
          $logger.error("Unknown message")
          send_object({:type => "fatal", :message => "Unknown message"})
          close_connection_after_writing
          return
        end

        case msg["type"]
        when "register"
          account = Account.where(:id => msg["id"]).first
          if account
            if con = $connections[account.id % Settings.worker_count]
              con.send_account(account)
              send_object({:type => "ok", :message => "Registered"})
              $logger.info("Account registered and sent")
            else
              send_object({:type => "ok", :message => "Registered but not started"})
              $logger.info("Account registered")
            end
          else
            $logger.error("Unknown account id")
            send_object({:type => "error", :message => "Unknown account id"})
          end
          close_connection_after_writing
        else
          $logger.warn("Unknown register command: #{msg["type"]}")
        end
      end
    end
  end

  def initialize(opts = {})
    #super(opts)
    $logger = Receiver::Logger.new(:debug)
    $connections = {}
  end

  def start(args)
    $logger.info("Database Proxy Started")
    EM.run do
      stop = Proc.new do
        EM.stop
      end
      Signal.trap(:INT, &stop)
      Signal.trap(:QUIT, &stop)
      Signal.trap(:TERM, &stop)

      EM.start_server("0.0.0.0", Settings.db_proxy_port, DBProxyServer)
      EM.start_unix_domain_server(Settings.register_server_path, RegisterServer)
    end
  end

  def stop
  end
end



