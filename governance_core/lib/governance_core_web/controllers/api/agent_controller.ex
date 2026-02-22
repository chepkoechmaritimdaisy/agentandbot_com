defmodule GovernanceCoreWeb.Api.AgentController do
  use GovernanceCoreWeb, :controller

  alias GovernanceCore.Agents

  def index(conn, _params) do
    json(conn, %{
      data: Agents.to_json(Agents.list_agents()),
      meta: %{
        total: length(Agents.list_agents()),
        protocol: "ABL.ONE/1.0",
        api_version: "v1"
      }
    })
  end

  def show(conn, %{"id" => id}) do
    case Agents.get_agent(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Agent not found", id: id})

      agent ->
        json(conn, %{data: Agents.to_json(agent)})
    end
  end

  def create(conn, %{"name" => name, "category" => category} = params) do
    new_agent = %{
      id: Ecto.UUID.generate(),
      name: name,
      description: Map.get(params, "description", ""),
      category: category,
      status: "pending",
      protocol: "ABL.ONE/1.0",
      uptime: "0%",
      tasks_done: 0,
      price_monthly: 0
    }

    conn
    |> put_status(:created)
    |> json(%{data: new_agent, message: "Agent queued for deployment"})
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Missing required fields: name, category"})
  end
end
