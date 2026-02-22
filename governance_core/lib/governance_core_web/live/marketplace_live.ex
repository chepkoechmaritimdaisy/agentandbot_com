defmodule GovernanceCoreWeb.MarketplaceLive do
  use GovernanceCoreWeb, :live_view

  alias GovernanceCore.Agents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       agents: Agents.list_agents(),
       filter: "all",
       search: "",
       page_title: "Marketplace",
       current_path: "/marketplace"
     ), layout: {GovernanceCoreWeb.Layouts, :app}}
  end

  @impl true
  def handle_event("filter", %{"category" => category}, socket) do
    {:noreply, assign(socket, filter: category)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, assign(socket, search: query)}
  end

  defp visible_agents(agents, filter, search) do
    agents
    |> filter_by_category(filter)
    |> filter_by_search(search)
  end

  defp filter_by_category(agents, "all"), do: agents

  defp filter_by_category(agents, cat),
    do: Enum.filter(agents, &(String.downcase(&1.category) == String.downcase(cat)))

  defp filter_by_search(agents, ""), do: agents

  defp filter_by_search(agents, q) do
    q_down = String.downcase(q)

    Enum.filter(agents, fn a ->
      String.contains?(String.downcase(a.name), q_down) ||
        String.contains?(String.downcase(a.description), q_down)
    end)
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
    <div class="mkt-wrap">
      <div class="mkt-header animate-fade-in-up">
        <h1 class="mkt-title">Agent Marketplace</h1>
        <p class="mkt-sub">Deploy a pre-built agent in one click. No setup required.</p>
      </div>

      <%!-- TOOLBAR: Filters + Search --%>
      <div class="mkt-toolbar animate-fade-in">
        <div class="mkt-filters">
          <button class={"filter-btn #{if @filter == "all", do: "active"}"} phx-click="filter" phx-value-category="all">All</button>
          <button class={"filter-btn #{if @filter == "Finance", do: "active"}"} phx-click="filter" phx-value-category="Finance">Finance</button>
          <button class={"filter-btn #{if @filter == "Research", do: "active"}"} phx-click="filter" phx-value-category="Research">Research</button>
          <button class={"filter-btn #{if @filter == "Communication", do: "active"}"} phx-click="filter" phx-value-category="Communication">Communication</button>
          <button class={"filter-btn #{if @filter == "Data", do: "active"}"} phx-click="filter" phx-value-category="Data">Data</button>
          <button class={"filter-btn #{if @filter == "Enterprise", do: "active"}"} phx-click="filter" phx-value-category="Enterprise">Enterprise</button>
        </div>
        <div class="search-wrap">
          <span class="search-icon">🔍</span>
          <input
            type="text"
            class="input-search"
            placeholder="Search agents..."
            phx-keyup="search"
            phx-key="Enter"
            name="q"
            value={@search}
            phx-debounce="300"
          />
        </div>
      </div>

      <%!-- AGENT GRID --%>
      <div class="agents-grid stagger">
        <%= for agent <- visible_agents(@agents, @filter, @search) do %>
          <div class="agent-card animate-fade-in-up">
            <div class="card-top">
              <div>
                <p class="card-name"><%= agent.name %></p>
                <p class="card-cat"><%= agent.category %></p>
              </div>
              <div class="status-badge">
                <span class={"status-dot #{status_class(agent.status)}"}></span>
                <%= status_label(agent.status) %>
              </div>
            </div>

            <p class="card-desc"><%= agent.description %></p>

            <div class="card-stats">
              <div class="stat">
                <div class="stat-val"><%= agent.uptime %></div>
                <div class="stat-lbl">Uptime</div>
              </div>
              <div class="stat">
                <div class="stat-val"><%= format_number(agent.tasks_done) %></div>
                <div class="stat-lbl">Tasks done</div>
              </div>
            </div>

            <div class="card-footer">
              <div class="card-price">
                $<%= agent.price_monthly %><span class="price-period">/month</span>
              </div>
              <a href={"/agents/#{agent.id}"} class="btn-deploy">Deploy →</a>
            </div>
          </div>
        <% end %>

        <%= if visible_agents(@agents, @filter, @search) == [] do %>
          <div class="empty-state">
            <p class="empty-title">No agents found.</p>
            <p class="empty-desc">Try a different filter or search term.</p>
            <a href="/agents/new" class="btn-deploy">Create Agent →</a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
