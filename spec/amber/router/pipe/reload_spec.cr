require "../../../../spec_helper"

module Amber
  module Pipe
    describe Reload do
      it "client should contain injected code" do
        pipeline = Pipeline.new
        request = HTTP::Request.new("GET", "/reload")

        Amber::Server.router.draw :web do
          get "/reload", HelloController, :world
        end

        pipeline.build :web do
          plug Amber::Pipe::Reload.new
        end

        pipeline.prepare_pipelines

        response = create_request_and_return_io(pipeline, request)
        response.body.should contain "Code injected by Amber Framework"
      end
    end
  end
end
