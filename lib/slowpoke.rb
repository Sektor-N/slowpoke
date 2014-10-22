require "slowpoke/version"
require "rack-timeout"
require "robustly"
require "slowpoke/railtie"
require "action_view/template"
require "action_controller/base"
require "active_record/connection_adapters/postgresql_adapter"
require "action_dispatch/middleware/exception_wrapper"

module Slowpoke
  class << self
    attr_accessor :database_timeout
  end

  def self.timeout
    @timeout ||= (ENV["TIMEOUT"] || 15).to_i
  end

  def self.timeout=(timeout)
    @timeout = Rack::Timeout.timeout = timeout
  end
end

# remove noisy logger
Rack::Timeout.unregister_state_change_observer(:logger)

ActionDispatch::ExceptionWrapper.rescue_responses["Rack::Timeout::RequestTimeoutError"] = :service_unavailable

Rack::Timeout.register_state_change_observer(:slowpoke) do |env|
  case env["rack-timeout.info"].state
  when :timed_out
    env["slowpoke.timed_out"] = true

    # TODO better payload
    ActiveSupport::Notifications.instrument("timeout.slowpoke", {})
  when :completed
    # can't do in timed_out state

    if env["slowpoke.timed_out"]
      # extremely important
      # protect the process with a restart
      # https://github.com/heroku/rack-timeout/issues/39
      Process.kill "QUIT", Process.pid
    end
  end
end

# bubble exceptions correctly
class ActionController::Base

  around_filter :bubble_timeout

  private

  def bubble_timeout
    yield
  rescue => exception
    if exception.respond_to?(:original_exception) and exception.original_exception.is_a?(Rack::Timeout::Error)
      raise exception.original_exception
    else
      raise exception
    end
  end
end

# database timeout
class ActiveRecord::ConnectionAdapters::PostgreSQLAdapter

  def configure_connection_with_statement_timeout
    configure_connection_without_statement_timeout
    safely do
      timeout = Slowpoke.database_timeout || Slowpoke.timeout
      if ActiveRecord::Base.logger
        ActiveRecord::Base.logger.silence do
          execute("SET statement_timeout = #{timeout * 1000}")
        end
      else
        execute("SET statement_timeout = #{timeout * 1000}")
      end
    end
  end
  alias_method_chain :configure_connection, :statement_timeout

end
