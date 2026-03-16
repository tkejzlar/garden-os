require_relative "../models/succession_plan"
require_relative "../models/task"

class GardenApp
  get "/succession" do
    @plans = SuccessionPlan.all
    erb :succession
  end

  get "/api/succession" do
    plans = SuccessionPlan.all.map do |sp|
      completed = Task.where(task_type: "sow")
                      .where(Sequel.like(:title, "%#{sp.crop}%"))
                      .where(status: "done").count
      upcoming = Task.where(task_type: "sow")
                     .where(Sequel.like(:title, "%#{sp.crop}%"))
                     .exclude(status: "done").first

      sp.values.merge(
        completed_sowings: completed,
        next_sowing: upcoming&.values,
        next_sowing_date: sp.next_sowing_date(completed)&.to_s
      )
    end
    json plans
  end
end
