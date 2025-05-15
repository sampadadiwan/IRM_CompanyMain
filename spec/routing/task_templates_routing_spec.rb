require "rails_helper"

RSpec.describe TaskTemplatesController, type: :routing do
  describe "routing" do
    it "routes to #index" do
      expect(get: "/task_templates").to route_to("task_templates#index")
    end

    it "routes to #new" do
      expect(get: "/task_templates/new").to route_to("task_templates#new")
    end

    it "routes to #show" do
      expect(get: "/task_templates/1").to route_to("task_templates#show", id: "1")
    end

    it "routes to #edit" do
      expect(get: "/task_templates/1/edit").to route_to("task_templates#edit", id: "1")
    end


    it "routes to #create" do
      expect(post: "/task_templates").to route_to("task_templates#create")
    end

    it "routes to #update via PUT" do
      expect(put: "/task_templates/1").to route_to("task_templates#update", id: "1")
    end

    it "routes to #update via PATCH" do
      expect(patch: "/task_templates/1").to route_to("task_templates#update", id: "1")
    end

    it "routes to #destroy" do
      expect(delete: "/task_templates/1").to route_to("task_templates#destroy", id: "1")
    end
  end
end
