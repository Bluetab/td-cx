defmodule TdCx.Sources.JobsTest do
  use TdCx.DataCase

  alias TdCx.Sources.Jobs

  describe "jobs" do
    alias TdCx.Sources.Jobs.Job

    test "create_job/1 with valid data creates a job" do
      source = insert(:source)
      assert {:ok, %Job{} = job} = Jobs.create_job(%{source_id: source.id})
      assert job.source_id == source.id
      assert not is_nil(job.external_id)
    end

    test "get_job!/2 will get a job with its events" do
      fixture = insert(:job)
      event = insert(:event, job: fixture)

      assert %Job{id: id, events: events, external_id: external_id} =
               Jobs.get_job!(fixture.external_id, [:events])

      assert id == fixture.id
      assert external_id == fixture.external_id
      assert length(events) == 1
      assert Enum.any?(events, &(&1.id == event.id))
    end
  end
end
