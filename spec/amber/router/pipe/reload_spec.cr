require "../../../../spec_helper"

module Amber
  module Pipe
    describe Reload do
      pipeline = Pipeline.new
      request = HTTP::Request.new("GET", "/reload")

      pipeline.build :web do
        plug Amber::Pipe::Reload.new
      end

      Amber::Server.router.draw :web do
        get "/reload", HelloController, :world
      end

      it "client should contain injected code" do
        response = create_request_and_return_io(pipeline, request)
        response.body.should contain "Code injected by Amber Framework"
      end
    end
  end
end
