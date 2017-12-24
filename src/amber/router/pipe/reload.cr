require "../../support/client_reload"

module Amber
  module Pipe
    # Reload clients browsers using `ClientReload`.
    #
    # NOTE: Amber::Pipe::Reload is intended for use in a development environment.
    # ```
    # pipeline :web do
    #   plug Amber::Pipe::Reload.new
    # end
    # ```
    class Reload < Base
      def initialize
        Support::ClientReload.new
        super
      end

      def call(context : HTTP::Server::Context)
        context.response.print Support::ClientReload::INJECTED_CODE
        context.response.headers["content-type"] = "text/html"
        call_next(context)
      end
    end
  end
end
