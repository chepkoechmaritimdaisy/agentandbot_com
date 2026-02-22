defmodule GovernanceCoreWeb.Api.AgentController do
  use GovernanceCoreWeb, :controller

  @agents [
    %{
      id: "research-pro",
      name: "ResearchAgent Pro",
      description: "Scans and summarizes any topic from the web.",
      category: "Research",
      status: "active",
      protocol: "ABL.ONE/1.0",
      uptime: "99.8%",
      tasks_done: 1_420,
      price_monthly: 29
    },
    %{
      id: "invoice-agent",
      name: "Invoice Agent",
      description: "Reads invoices from email or Telegram, extracts data, exports to CSV.",
      category: "Finance",
      status: "active",
      protocol: "ABL.ONE/1.0",
      uptime: "99.9%",
      tasks_done: 8_203,
      price_monthly: 49
    },
    %{
      id: "expense-agent",
      name: "Expense Agent",
      description: "OCR receipts, categorize expenses, prepare accounting-ready records.",
      category: "Finance",
      status: "active",
      protocol: "ABL.ONE/1.0",
      uptime: "99.5%",
      tasks_done: 3_870,
      price_monthly: 39
    },
    %{
      id: "email-agent",
      name: "Email Agent",
      description: "Monitors inbox, drafts replies, routes messages to the right agent.",
      category: "Communication",
      status: "active",
      protocol: "ABL.ONE/1.0",
      uptime: "99.7%",
      tasks_done: 12_501,
      price_monthly: 19
    },
    %{
      id: "data-sync",
      name: "DataSync Agent",
      description: "Keeps your databases and spreadsheets in sync automatically.",
      category: "Data",
      status: "idle",
      protocol: "ABL.ONE/1.0",
      uptime: "98.1%",
      tasks_done: 642,
      price_monthly: 59
    },
    %{
      id: "sap-agent",
      name: "SAP Close Agent",
      description: "Runs month-end closing tasks in SAP with audit trail.",
      category: "Enterprise",
      status: "active",
      protocol: "ABL.ONE/1.0",
      uptime: "99.9%",
      tasks_done: 290,
      price_monthly: 149
    }
  ]

  def index(conn, _params) do
    json(conn, %{
      data: @agents,
      meta: %{
        total: length(@agents),
        protocol: "ABL.ONE/1.0",
        api_version: "v1"
      }
    })
  end

  def show(conn, %{"id" => id}) do
    case Enum.find(@agents, &(&1.id == id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Agent not found", id: id})

      agent ->
        json(conn, %{data: agent})
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
