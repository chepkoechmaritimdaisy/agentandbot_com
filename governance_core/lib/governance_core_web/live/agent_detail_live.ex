defmodule GovernanceCoreWeb.AgentDetailLive do
  use GovernanceCoreWeb, :live_view

  @agents %{
    "research-pro" => %{
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
    "invoice-agent" => %{
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
    "expense-agent" => %{
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
    "email-agent" => %{
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
    "data-sync" => %{
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
    "sap-agent" => %{
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
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    agent = Map.get(@agents, id)

    {:ok,
     assign(socket,
       agent: agent,
       agent_id: id,
       page_title: if(agent, do: agent.name, else: "Agent Not Found"),
       current_path: "/agents/#{id}"
     ), layout: {GovernanceCoreWeb.Layouts, :app}}
  end

  defp status_class(:active), do: "active"
  defp status_class(:idle), do: "idle"
  defp status_class(:error), do: "error"

  defp status_label(:active), do: "Active"
  defp status_label(:idle), do: "Idle"
  defp status_label(:error), do: "Error"

  defp format_number(n) do
    n
    |> :erlang.integer_to_list()
    |> List.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+$)/, "\\1,")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="detail-wrap">
      <%= if @agent do %>
        <%!-- BREADCRUMB --%>
        <div class="detail-breadcrumb animate-fade-in">
          <a href="/marketplace" class="breadcrumb-link">Marketplace</a>
          <span class="breadcrumb-sep">→</span>
          <span class="breadcrumb-current"><%= @agent.name %></span>
        </div>

        <%!-- HEADER --%>
        <div class="detail-header animate-fade-in-up">
          <div class="detail-header-info">
            <h1 class="detail-name"><%= @agent.name %></h1>
            <span class="detail-cat"><%= @agent.category %></span>
          </div>
          <div class="status-badge">
            <span class={"status-dot #{status_class(@agent.status)}"}></span>
            <%= status_label(@agent.status) %>
          </div>
        </div>

        <p class="detail-desc animate-fade-in"><%= @agent.description %></p>

        <%!-- STATS GRID --%>
        <div class="detail-stats stagger">
          <div class="detail-stat-card animate-fade-in-up">
            <div class="stat-val"><%= @agent.uptime %></div>
            <div class="stat-lbl">Uptime</div>
          </div>
          <div class="detail-stat-card animate-fade-in-up">
            <div class="stat-val"><%= format_number(@agent.tasks_done) %></div>
            <div class="stat-lbl">Tasks Done</div>
          </div>
          <div class="detail-stat-card animate-fade-in-up">
            <div class="stat-val">$<%= @agent.price_monthly %></div>
            <div class="stat-lbl">Per Month</div>
          </div>
          <div class="detail-stat-card animate-fade-in-up">
            <div class="stat-val"><%= @agent.runtime %></div>
            <div class="stat-lbl">Runtime</div>
          </div>
        </div>

        <%!-- SPECS --%>
        <div class="detail-specs animate-fade-in-up">
          <div class="spec-title">Specifications</div>
          <div class="spec-grid">
            <div class="spec-row">
              <span class="spec-key">Protocol</span>
              <span class="spec-val"><%= @agent.protocol %></span>
            </div>
            <div class="spec-row">
              <span class="spec-key">Memory</span>
              <span class="spec-val"><%= @agent.memory %></span>
            </div>
            <div class="spec-row">
              <span class="spec-key">CPU</span>
              <span class="spec-val"><%= @agent.cpu %></span>
            </div>
            <div class="spec-row">
              <span class="spec-key">Owner</span>
              <span class="spec-val"><%= @agent.owner %></span>
            </div>
            <div class="spec-row">
              <span class="spec-key">Created</span>
              <span class="spec-val"><%= @agent.created %></span>
            </div>
          </div>
        </div>

        <%!-- LIVE LOG --%>
        <div class="detail-log animate-fade-in-up">
          <div class="log-title">Activity Log</div>
          <div class="log-panel">
            <%= for {line, i} <- Enum.with_index(@agent.logs) do %>
              <div class={"log-line #{if i == length(@agent.logs) - 1, do: "log-active"}"}><%= line %></div>
            <% end %>
            <div class="cursor-blink">█</div>
          </div>
        </div>

        <%!-- CTA --%>
        <div class="detail-actions animate-fade-in-up">
          <a href={"/agents/new?template=#{@agent.id}"} class="btn-hero">İşe Al →</a>
          <a href="/marketplace" class="btn-ghost">← Marketplace</a>
        </div>

      <% else %>
        <%!-- EMPTY STATE --%>
        <div class="empty-state animate-fade-in-up">
          <p class="empty-title">Agent not found.</p>
          <p class="empty-desc">The agent you're looking for doesn't exist or has been removed.</p>
          <a href="/marketplace" class="btn-deploy">Browse Marketplace →</a>
        </div>
      <% end %>
    </div>
    """
  end
end
