module BoltSpec
  module Conn
    def conn_info(transport)
      tu = transport.upcase
      case transport
      when 'ssh'
        default_port = 2224
        default_user = 'bolt'
        default_password = 'bolt'
        default_key = Dir["spec/fixtures/keys/id_rsa"]
      when 'winrm'
        default_port = 25985
        default_user = 'vagrant'
        default_password = 'vagrant'
        default_key = Dir[".vagrant/**/private_key"]
      else
        raise Error, "The transport must be either 'ssh' or 'winrm'"
      end

      {
        protocol: transport,
        host: ENV["BOLT_#{tu}_HOST"] || "localhost",
        user: ENV["BOLT_#{tu}_USER"] || default_user,
        password: ENV["BOLT_#{tu}_PASSWORD"] || default_password,
        port: ENV["BOLT_#{tu}_PORT"] || default_port,
        key: ENV["BOLT_#{tu}_KEY"] || default_key
      }
    end

    def conn_uri(transport, include_password = false)
      conn = conn_info(transport)
      passwd = include_password ? ":#{conn[:password]}" : ''
      "#{conn[:protocol]}://#{conn[:user]}#{passwd}@#{conn[:host]}:#{conn[:port]}"
    end
  end
end
