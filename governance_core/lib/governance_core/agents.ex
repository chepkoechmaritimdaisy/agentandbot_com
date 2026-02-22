defmodule GovernanceCore.Agents do
  @moduledoc """
  Centralized agent data and operations.
  Single source of truth for agent information across
  LiveView pages and API controllers.

  Future: replace @agents with Ecto/Repo queries.
  """

  @agents [
    %{
      id: "research-pro",
      name: "ResearchAgent Pro",
      description:
        "Scans and summarizes any topic from the web. Crawls 50+ sources in under 2 minutes and delivers structured reports.",
      category: "Research",
      status: :active,
      uptime: "99.8%",
      tasks_done: 1_420,
      price_monthly: 29,
      protocol: "ABL.ONE/1.0",
      runtime: "4h 23m",
      memory: "128MB",
      cpu: "0.5 vCPU",
      owner: "agentandbot.com",
      created: "2026-01-15",
      logs: [
        "[14:22] Task assigned: \"Analyze competitor pricing\"",
        "[14:23] Searching 24 sources...",
        "[14:35] Extracting structured data...",
        "[14:42] Generating summary report...",
        "[14:45] Report delivered — 4,200 words",
        "[14:45] Budget used: $1.40 / $5.00"
      ]
    },
    %{
      id: "invoice-agent",
      name: "Invoice Agent",
      description:
        "Reads invoices from email or Telegram, extracts data fields (amount, date, vendor), and exports to accounting-ready CSV format.",
      category: "Finance",
      status: :active,
      uptime: "99.9%",
      tasks_done: 8_203,
      price_monthly: 49,
      protocol: "ABL.ONE/1.0",
      runtime: "12h 05m",
      memory: "256MB",
      cpu: "1 vCPU",
      owner: "agentandbot.com",
      created: "2026-01-10",
      logs: [
        "[09:01] Monitoring inbox for new invoices...",
        "[09:14] New invoice detected: vendor=Acme Corp",
        "[09:14] OCR processing...",
        "[09:15] Fields extracted: amount=$2,450.00 date=2026-02-20",
        "[09:15] Exported to monthly_invoices.csv",
        "[09:15] Task complete"
      ]
    },
    %{
      id: "expense-agent",
      name: "Expense Agent",
      description:
        "OCR receipts, categorize expenses, prepare accounting-ready records. Supports multi-currency and tax categories.",
      category: "Finance",
      status: :active,
      uptime: "99.5%",
      tasks_done: 3_870,
      price_monthly: 39,
      protocol: "ABL.ONE/1.0",
      runtime: "6h 12m",
      memory: "192MB",
      cpu: "0.5 vCPU",
      owner: "agentandbot.com",
      created: "2026-01-20",
      logs: [
        "[11:30] Receipt scan initiated",
        "[11:30] OCR processing 3 images...",
        "[11:31] Categorized: Office Supplies ($45.20)",
        "[11:31] Categorized: Travel ($128.50)",
        "[11:31] Categorized: Software ($99.00)",
        "[11:31] Export ready"
      ]
    },
    %{
      id: "email-agent",
      name: "Email Agent",
      description:
        "Monitors inbox, drafts replies, routes messages to the right agent. Handles 500+ emails per day with smart prioritization.",
      category: "Communication",
      status: :active,
      uptime: "99.7%",
      tasks_done: 12_501,
      price_monthly: 19,
      protocol: "ABL.ONE/1.0",
      runtime: "24h 00m",
      memory: "64MB",
      cpu: "0.25 vCPU",
      owner: "agentandbot.com",
      created: "2026-01-05",
      logs: [
        "[08:00] Inbox monitoring active",
        "[08:12] Priority email from: board@company.com",
        "[08:12] Draft reply generated (awaiting approval)",
        "[08:30] 14 emails routed to InvoiceAgent",
        "[08:45] 3 emails archived (spam detected)",
        "[09:00] Hourly summary ready"
      ]
    },
    %{
      id: "data-sync",
      name: "DataSync Agent",
      description:
        "Keeps your databases and spreadsheets in sync automatically. Supports PostgreSQL, MySQL, Google Sheets, and Excel.",
      category: "Data",
      status: :idle,
      uptime: "98.1%",
      tasks_done: 642,
      price_monthly: 59,
      protocol: "ABL.ONE/1.0",
      runtime: "0h 00m",
      memory: "512MB",
      cpu: "1 vCPU",
      owner: "agentandbot.com",
      created: "2026-02-01",
      logs: [
        "[--:--] Agent idle — waiting for sync schedule",
        "[--:--] Last sync: 2026-02-22 06:00 UTC",
        "[--:--] Next sync: 2026-02-23 06:00 UTC"
      ]
    },
    %{
      id: "sap-agent",
      name: "SAP Close Agent",
      description:
        "Runs month-end closing tasks in SAP with full audit trail. Handles FI/CO postings, reconciliation, and report generation.",
      category: "Enterprise",
      status: :active,
      uptime: "99.9%",
      tasks_done: 290,
      price_monthly: 149,
      protocol: "ABL.ONE/1.0",
      runtime: "2h 45m",
      memory: "1024MB",
      cpu: "2 vCPU",
      owner: "agentandbot.com",
      created: "2026-01-25",
      logs: [
        "[20:00] Month-end close initiated for period 2026-02",
        "[20:05] FI postings validated: 1,247 documents",
        "[20:15] CO settlement running...",
        "[20:30] Reconciliation check: PASS",
        "[20:45] Generating management reports...",
        "[20:50] Close complete — audit trail saved"
      ]
    }
  ]

  @doc "Returns all agents."
  def list_agents, do: @agents

  @doc "Returns a single agent by ID, or nil."
  def get_agent(id), do: Enum.find(@agents, &(&1.id == id))

  @doc "Returns agents filtered by category (case-insensitive)."
  def list_by_category("all"), do: @agents

  def list_by_category(cat) do
    Enum.filter(@agents, &(String.downcase(&1.category) == String.downcase(cat)))
  end

  @doc "Search agents by name or description."
  def search(query) when query in ["", nil], do: @agents

  def search(query) do
    q = String.downcase(query)

    Enum.filter(@agents, fn a ->
      String.contains?(String.downcase(a.name), q) ||
        String.contains?(String.downcase(a.description), q)
    end)
  end

  @doc "Filter + search combined."
  def filter(category, search_query) do
    list_by_category(category) |> do_search(search_query)
  end

  defp do_search(agents, q) when q in ["", nil], do: agents

  defp do_search(agents, q) do
    q_down = String.downcase(q)

    Enum.filter(agents, fn a ->
      String.contains?(String.downcase(a.name), q_down) ||
        String.contains?(String.downcase(a.description), q_down)
    end)
  end

  @doc "Returns agents as JSON-safe maps (atoms → strings for status)."
  def to_json(agents) when is_list(agents), do: Enum.map(agents, &to_json/1)

  def to_json(%{status: status} = agent) do
    Map.put(agent, :status, Atom.to_string(status))
  end

  @doc "Dashboard summary stats."
  def dashboard_stats do
    agents = list_agents()

    %{
      total: length(agents),
      active: Enum.count(agents, &(&1.status == :active)),
      tasks_today:
        Enum.reduce(agents, 0, fn a, acc ->
          # Simulated daily tasks based on total
          acc + div(a.tasks_done, 30)
        end)
    }
  end
end
