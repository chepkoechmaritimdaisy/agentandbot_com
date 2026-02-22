defmodule GovernanceCoreWeb.DashboardLive do
  use GovernanceCoreWeb, :live_view

  alias GovernanceCore.Agents

  @impl true
  def mount(_params, _session, socket) do
    agents = Agents.list_agents()
    stats = Agents.dashboard_stats()

    {:ok,
     assign(socket,
       agents: agents,
       total_agents: stats.total,
       active_agents: stats.active,
       tasks_today: stats.tasks_today,
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
            <span class="dash-col">Tasks Done</span>
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
              <span class="dash-col dash-mono"><%= agent.tasks_done %></span>
              <span class="dash-col dash-mono"><%= agent.runtime %></span>
              <span class="dash-col dash-mono">$<%= agent.price_monthly %>/mo</span>
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
