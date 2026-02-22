defmodule GovernanceCoreWeb.Api.TaskController do
  use GovernanceCoreWeb, :controller

  @sample_tasks %{
    "task-001" => %{
      id: "task-001",
      agent_id: "research-pro",
      type: "research",
      status: "completed",
      input: "Analyze competitor pricing for Q1 2026",
      output: "Report delivered — 4,200 words covering 24 sources",
      created_at: "2026-02-22T14:22:00Z",
      completed_at: "2026-02-22T14:45:00Z",
      cost: "$1.40"
    }
  }

  def create(conn, %{"agent_id" => agent_id, "input" => input} = _params) do
    task = %{
      id: "task-#{:erlang.unique_integer([:positive])}",
      agent_id: agent_id,
      type: "custom",
      status: "queued",
      input: input,
      output: nil,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      completed_at: nil,
      cost: "$0.00"
    }

    conn
    |> put_status(:accepted)
    |> json(%{data: task, message: "Task submitted to #{agent_id}"})
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Missing required fields: agent_id, input"})
  end

  def show(conn, %{"id" => id}) do
    case Map.get(@sample_tasks, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Task not found", id: id})

      task ->
        json(conn, %{data: task})
    end
  end
end
