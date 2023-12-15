require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::BlueskyAuthorfeedAgent do
  before(:each) do
    @valid_options = Agents::BlueskyAuthorfeedAgent.new.default_options
    @checker = Agents::BlueskyAuthorfeedAgent.new(:name => "BlueskyAuthorfeedAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
