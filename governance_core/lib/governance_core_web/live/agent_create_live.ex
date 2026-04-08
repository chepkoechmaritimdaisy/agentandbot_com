defmodule GovernanceCoreWeb.AgentCreateLive do
  use GovernanceCoreWeb, :live_view
  alias GovernanceCore.Agents

  @categories ["Research", "Finance", "Communication", "Data", "Enterprise", "Custom"]
  @protocols ["ABL.ONE/1.0"]
  @sizes [
    %{id: "pico", label: "PicoClaw", memory: "10MB", cpu: "0.1 vCPU", price: 9},
    %{id: "micro", label: "Micro Agent", memory: "64MB", cpu: "0.25 vCPU", price: 19},
    %{id: "standard", label: "Standard Agent", memory: "256MB", cpu: "0.5 vCPU", price: 49},
    %{id: "pro", label: "Pro Agent", memory: "1GB", cpu: "2 vCPU", price: 149}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       step: 1,
       name: "",
       description: "",
       category: "",
       protocol: "ABL.ONE/1.0",
       size: "standard",
       categories: @categories,
       protocols: @protocols,
       sizes: @sizes,
       page_title: "Create Agent",
       current_path: "/agents/new"
     ), layout: {GovernanceCoreWeb.Layouts, :app}}
  end

  @impl true
  def handle_event("next", _params, %{assigns: %{step: step}} = socket) when step < 3 do
    {:noreply, assign(socket, step: step + 1)}
  end

  @impl true
  def handle_event("back", _params, %{assigns: %{step: step}} = socket) when step > 1 do
    {:noreply, assign(socket, step: step - 1)}
  end

  @impl true
  def handle_event("update_field", %{"field" => "name", "value" => val}, socket) do
    {:noreply, assign(socket, name: val)}
  end

  @impl true
  def handle_event("update_field", %{"field" => "description", "value" => val}, socket) do
    {:noreply, assign(socket, description: val)}
  end

  @impl true
  def handle_event("select_category", %{"cat" => cat}, socket) do
    {:noreply, assign(socket, category: cat)}
  end

  @impl true
  def handle_event("select_size", %{"size" => size}, socket) do
    {:noreply, assign(socket, size: size)}
  end

  @impl true
  def handle_event("launch", _params, socket) do
    agent_params = %{
      name: socket.assigns.name,
      description: socket.assigns.description,
      category: socket.assigns.category,
      protocol: socket.assigns.protocol,
      owner: "local_user",
      status: "active",
      metadata: %{
        size: socket.assigns.size,
        hardware: "Local Mock Node"
      }
    }

    case Agents.create_agent(agent_params) do
      {:ok, _agent} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agent \"#{socket.assigns.name}\" created and launched!")
         |> push_navigate(to: "/dashboard")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Launch failed. Check required fields.")}
    end
  end

  defp selected_size(sizes, size_id) do
    Enum.find(sizes, List.first(sizes), &(&1.id == size_id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="create-wrap">
      <%!-- PROGRESS BAR --%>
      <div class="create-progress animate-fade-in">
        <div class={"progress-step #{if @step >= 1, do: "active"}"}>
          <span class="progress-num">1</span>
          <span class="progress-label">Identity</span>
        </div>
        <div class="progress-line"></div>
        <div class={"progress-step #{if @step >= 2, do: "active"}"}>
          <span class="progress-num">2</span>
          <span class="progress-label">Resources</span>
        </div>
        <div class="progress-line"></div>
        <div class={"progress-step #{if @step >= 3, do: "active"}"}>
          <span class="progress-num">3</span>
          <span class="progress-label">Launch</span>
        </div>
      </div>

      <%!-- STEP 1: IDENTITY --%>
      <%= if @step == 1 do %>
        <div class="create-step animate-fade-in-up">
          <h2 class="create-step-title">Name your agent</h2>
          <p class="create-step-sub">Give your agent an identity and purpose.</p>

          <div class="form-group">
            <label class="form-label">Agent Name</label>
            <input
              type="text"
              class="form-input"
              placeholder="e.g. ResearchAgent Pro"
              value={@name}
              phx-keyup="update_field"
              phx-value-field="name"
              phx-debounce="300"
            />
          </div>

          <div class="form-group">
            <label class="form-label">Description</label>
            <textarea
              class="form-textarea"
              placeholder="What does this agent do? (1–2 sentences)"
              phx-keyup="update_field"
              phx-value-field="description"
              phx-debounce="300"
            ><%= @description %></textarea>
          </div>

          <div class="form-group">
            <label class="form-label">Category</label>
            <div class="category-grid">
              <%= for cat <- @categories do %>
                <button
                  class={"category-btn #{if @category == cat, do: "selected"}"}
                  phx-click="select_category"
                  phx-value-cat={cat}
                >
                  <%= cat %>
                </button>
              <% end %>
            </div>
          </div>

          <div class="create-actions">
            <a href="/marketplace" class="btn-ghost">Cancel</a>
            <button class="btn-primary" phx-click="next">Next →</button>
          </div>
        </div>
      <% end %>

      <%!-- STEP 2: RESOURCES --%>
      <%= if @step == 2 do %>
        <div class="create-step animate-fade-in-up">
          <h2 class="create-step-title">Set resources</h2>
          <p class="create-step-sub">Choose the size and protocol for your agent.</p>

          <div class="form-group">
            <label class="form-label">Agent Size</label>
            <div class="size-grid">
              <%= for s <- @sizes do %>
                <button
                  class={"size-card #{if @size == s.id, do: "selected"}"}
                  phx-click="select_size"
                  phx-value-size={s.id}
                >
                  <div class="size-name"><%= s.label %></div>
                  <div class="size-spec"><%= s.memory %> · <%= s.cpu %></div>
                  <div class="size-price">$<%= s.price %>/mo</div>
                </button>
              <% end %>
            </div>
          </div>

          <div class="form-group">
            <label class="form-label">Protocol</label>
            <div class="proto-badge">
              <span class="status-dot active"></span>
              ABL.ONE/1.0
            </div>
            <p class="form-hint">8-byte binary frames · CRC32 verified · M2M auth</p>
          </div>

          <div class="create-actions">
            <button class="btn-ghost" phx-click="back">← Back</button>
            <button class="btn-primary" phx-click="next">Next →</button>
          </div>
        </div>
      <% end %>

      <%!-- STEP 3: REVIEW & LAUNCH --%>
      <%= if @step == 3 do %>
        <div class="create-step animate-fade-in-up">
          <h2 class="create-step-title">Review & Launch</h2>
          <p class="create-step-sub">Verify your agent configuration before deployment.</p>

          <div class="review-card">
            <div class="review-header">
              <span class="review-name"><%= if @name == "", do: "Unnamed Agent", else: @name %></span>
              <span class="status-badge">
                <span class="status-dot idle"></span>
                Ready
              </span>
            </div>

            <div class="review-rows">
              <div class="review-row">
                <span class="review-key">Category</span>
                <span class="review-val"><%= if @category == "", do: "—", else: @category %></span>
              </div>
              <div class="review-row">
                <span class="review-key">Description</span>
                <span class="review-val"><%= if @description == "", do: "—", else: @description %></span>
              </div>
              <% size = selected_size(@sizes, @size) %>
              <div class="review-row">
                <span class="review-key">Size</span>
                <span class="review-val"><%= size.label %> (<%= size.memory %> · <%= size.cpu %>)</span>
              </div>
              <div class="review-row">
                <span class="review-key">Protocol</span>
                <span class="review-val"><%= @protocol %></span>
              </div>
              <div class="review-row">
                <span class="review-key">Cost</span>
                <span class="review-val" style="color: var(--ok);">$<%= size.price %>/month</span>
              </div>
            </div>
          </div>

          <div class="create-actions">
            <button class="btn-ghost" phx-click="back">← Back</button>
            <button class="btn-hero" phx-click="launch">Başlat →</button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
