defmodule GovernanceCoreWeb.DashboardLive do
  use GovernanceCoreWeb, :live_view

  @agents [
    %{
      id: "research-pro",
      name: "ResearchAgent Pro",
      status: :active,
      tasks_today: 12,
      runtime: "4h 23m",
      cost_today: "$1.40"
    },
    %{
      id: "invoice-agent",
      name: "Invoice Agent",
      status: :active,
      tasks_today: 34,
      runtime: "12h 05m",
      cost_today: "$3.20"
    },
    %{
      id: "email-agent",
      name: "Email Agent",
      status: :active,
      tasks_today: 87,
      runtime: "24h 00m",
      cost_today: "$0.95"
    },
    %{
      id: "sap-agent",
      name: "SAP Close Agent",
      status: :active,
      tasks_today: 3,
      runtime: "2h 45m",
      cost_today: "$8.50"
    },
    %{
      id: "data-sync",
      name: "DataSync Agent",
      status: :idle,
      tasks_today: 0,
      runtime: "0h 00m",
      cost_today: "$0.00"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    total = length(@agents)
    active = Enum.count(@agents, &(&1.status == :active))
    tasks_today = Enum.reduce(@agents, 0, &(&1.tasks_today + &2))

    {:ok,
     assign(socket,
       agents: @agents,
       total_agents: total,
       active_agents: active,
       tasks_today: tasks_today,
       page_title: "Dashboard",
       current_path: "/dashboard"
     ), layout: {GovernanceCoreWeb.Layouts, :app}}
  end

  defp status_class(:active), do: "active"
  defp status_class(:idle), do: "idle"
  defp status_class(:error), do: "error"

  defp status_label(:active), do: "Active"
  defp status_label(:idle), do: "Idle"
  defp status_label(:error), do: "Error"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dash-wrap">
      <%!-- HEADER --%>
      <div class="dash-header animate-fade-in-up">
        <div>
          <h1 class="dash-title">Dashboard</h1>
          <p class="dash-sub">Monitor your running agents.</p>
        </div>
        <a href="/agents/new" class="btn-primary">Yeni Ekle →</a>
      </div>

      <%!-- STATS BAR --%>
      <div class="dash-stats stagger">
        <div class="dash-stat-card animate-fade-in-up">
          <div class="stat-val"><%= @total_agents %></div>
          <div class="stat-lbl">Total Agents</div>
        </div>
        <div class="dash-stat-card animate-fade-in-up">
          <div class="stat-val" style="color: var(--ok);"><%= @active_agents %></div>
          <div class="stat-lbl">Active</div>
        </div>
        <div class="dash-stat-card animate-fade-in-up">
          <div class="stat-val"><%= @tasks_today %></div>
          <div class="stat-lbl">Tasks Today</div>
        </div>
      </div>

      <%!-- AGENT LIST --%>
      <%= if @agents == [] do %>
        <div class="empty-state animate-fade-in-up">
          <p class="empty-title">No agents yet.</p>
          <p class="empty-desc">Create your first agent to get started.</p>
          <a href="/agents/new" class="btn-deploy">Create Agent →</a>
        </div>
      <% else %>
        <div class="dash-table animate-fade-in-up">
          <div class="dash-table-header">
            <span class="dash-col-name">Agent</span>
            <span class="dash-col">Status</span>
            <span class="dash-col">Tasks</span>
            <span class="dash-col">Runtime</span>
            <span class="dash-col">Cost</span>
            <span class="dash-col"></span>
          </div>
          <%= for agent <- @agents do %>
            <div class="dash-table-row">
              <span class="dash-col-name">
                <a href={"/agents/#{agent.id}"} class="dash-agent-link"><%= agent.name %></a>
              </span>
              <span class="dash-col">
                <span class="status-badge">
                  <span class={"status-dot #{status_class(agent.status)}"}></span>
                  <%= status_label(agent.status) %>
                </span>
              </span>
              <span class="dash-col dash-mono"><%= agent.tasks_today %></span>
              <span class="dash-col dash-mono"><%= agent.runtime %></span>
              <span class="dash-col dash-mono"><%= agent.cost_today %></span>
              <span class="dash-col">
                <a href={"/agents/#{agent.id}"} class="btn-outline btn-sm">View →</a>
              </span>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
