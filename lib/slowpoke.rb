# dependencies
require "rack/timeout/base"

# modules
require_relative "slowpoke/middleware"
require_relative "slowpoke/railtie"
require_relative "slowpoke/timeout"
require_relative "slowpoke/version"

module Slowpoke
  ENV_KEY = "slowpoke.timed_out".freeze

  def self.kill
    if defined?(::PhusionPassenger)
      `passenger-config detach-process #{Process.pid}`
    elsif defined?(::Puma)
      Process.kill("TERM", Process.pid)
    else
      Process.kill("QUIT", Process.pid)
    end
  end

  def self.on_timeout(&block)
    if block_given?
      @on_timeout = block
    else
      @on_timeout
    end
  end

  on_timeout do |env|
    next if Rails.env.development? || Rails.env.test?

    Slowpoke.kill
  end
end

Rack::Timeout.register_state_change_observer(:slowpoke) do |env|
  case env[Rack::Timeout::ENV_INFO_KEY].state
  when :timed_out
    env[Slowpoke::ENV_KEY] = true
    Process.kill("TTIN", Process.ppid)
  when :completed
    if env[Slowpoke::ENV_KEY]
      Process.kill("QUIT", Process.pid)
      Process.kill("TTOU", Process.ppid)
    end
  end
end
