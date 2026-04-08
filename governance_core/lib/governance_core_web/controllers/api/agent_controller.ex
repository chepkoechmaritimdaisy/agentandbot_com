defmodule GovernanceCoreWeb.Api.AgentController do
  use GovernanceCoreWeb, :controller

  alias GovernanceCore.Agents

  def index(conn, _params) do
    agents = Agents.list_agents()
    json(conn, %{
      data: agents,
      meta: %{
        total: length(agents),
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
        json(conn, %{data: agent})
    end
  end

  def create(conn, %{"name" => name, "category" => category} = params) do
    case Agents.create_agent(params) do
      {:ok, agent} ->
        conn
        |> put_status(:created)
        |> json(%{data: agent, message: "Identity Passport created & Agent queued for deployment"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: "Check required fields"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Missing required fields: name, category"})
  end
end
