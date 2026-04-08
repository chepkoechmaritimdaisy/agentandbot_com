defmodule GovernanceCoreWeb.AgentDetailLive do
  use GovernanceCoreWeb, :live_view

  alias GovernanceCore.Agents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    agent = Agents.get_agent(id)

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
  defp status_class("active"), do: "active"
  defp status_class("paused"), do: "idle"
  defp status_class("error"), do: "error"

  defp status_label(:active), do: "Active"
  defp status_label(:idle), do: "Idle"
  defp status_label(:error), do: "Error"
  defp status_label("active"), do: "Active"
  defp status_label("paused"), do: "Paused"
  defp status_label("error"), do: "Error"

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
          <div class="spec-title">Identity Passport</div>
          <div class="spec-grid">
            <div class="spec-row">
              <span class="spec-key">Type</span>
              <span class="spec-val"><%= String.capitalize(@agent.type) %></span>
            </div>
            <div class="spec-row">
              <span class="spec-key">Karma Score</span>
              <span class="spec-val"><%= @agent.trust_score %> / 100</span>
            </div>
            <div class="spec-row">
              <span class="spec-key">Hardware (GPU/RAM)</span>
              <span class="spec-val"><%= Map.get(@agent.metadata, "hardware", "Generic Node") %></span>
            </div>
            <div class="spec-row">
              <span class="spec-key">Owner</span>
              <span class="spec-val"><%= @agent.owner %></span>
            </div>
          </div>
        </div>

        <%!-- CAPABILITIES / CHANNELS --%>
        <div class="detail-specs animate-fade-in-up">
          <div class="spec-title">Swarm Capabilities</div>
          <div class="spec-grid">
            <div class="spec-row">
              <span class="spec-key">Telegram</span>
              <span class="spec-val"><%= if Map.get(@agent.metadata, "telegram_id"), do: "✅ Active", else: "⚪ Not Configured" %></span>
            </div>
            <div class="spec-row">
              <span class="spec-key">Email</span>
              <span class="spec-val">⚪ Available</span>
            </div>
            <div class="spec-row">
              <span class="spec-key">Markdown Baseline</span>
              <span class="spec-val">✅ Running (Fallback)</span>
            </div>
             <div class="spec-row">
              <span class="spec-key">Windmill (Workflow)</span>
              <span class="spec-val">⚡ Upgrade Pending</span>
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
