defmodule GovernanceCoreWeb.PersonaDirectoryLive do
  use GovernanceCoreWeb, :live_view
  alias GovernanceCore.Agents

  @impl true
  def mount(_params, _session, socket) do
    # Fetch real agents using the consolidated context
    agents = Agents.list_agents()

    {:ok, assign(socket, personas: agents, filter: "all")}
  end

  # Helper for persona cards if needed, or using component
  
  @impl true
  def render(assigns) do
    ~H"""
    <div id="persona-directory" class="space-y-8">
      <%!-- FILTERS AND SEARCH --%>
      <header class="flex flex-col md:flex-row items-center justify-between gap-6 pb-6 border-b border-base-content/5">
        <div class="flex items-center gap-2">
          <div class="join border border-base-content/10 bg-base-200">
            <button class={["btn btn-sm join-item px-6", @filter == "all" && "btn-active"]}>All</button>
            <button class={["btn btn-sm join-item px-6", @filter == "human" && "btn-active"]}>Humans</button>
            <button class={["btn btn-sm join-item px-6", @filter == "bot" && "btn-active"]}>Bots</button>
          </div>
          <div class="divider divider-horizontal mx-1"></div>
          <div class="join border border-base-content/10 bg-base-200">
            <button class="btn btn-sm join-item px-6 btn-ghost text-[10px] font-bold">Harezm Group</button>
            <button class="btn btn-sm join-item px-6 btn-ghost text-[10px] font-bold opacity-50">Guests</button>
          </div>
        </div>

        <div class="flex items-center gap-4 w-full md:w-auto">
          <div class="join w-full md:w-auto">
            <div class="input input-sm input-bordered join-item flex items-center gap-2">
              <.icon name="hero-magnifying-glass" class="size-4 opacity-50" />
              <input type="text" placeholder="Search agents..." class="bg-transparent border-none focus:outline-none" />
            </div>
            <a href="/agents/new" class="btn btn-sm btn-primary join-item px-6">+ Deploy</a>
          </div>
        </div>
      </header>

      <%!-- GRID OF PERSONAS --%>
      <section id="personas-grid" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        <div :for={persona <- @personas} class="card card-bordered bg-base-200 border-base-content/5 hover:border-base-content/20 transition-all">
          <div class="card-body p-4">
            <div class="flex items-center justify-between mb-4">
               <span class="text-[10px] font-bold uppercase opacity-50 tracking-widest"><%= persona.type %></span>
               <div class={"size-2 rounded-full #{if persona.status == "active", do: "bg-success", else: "bg-base-content/20"}"}></div>
            </div>
            <h3 class="card-title text-sm font-black mb-1"><%= persona.name %></h3>
            <p class="text-xs opacity-70 line-clamp-2"><%= persona.role %></p>
            
            <div class="mt-4 flex flex-wrap gap-1">
              <%= for skill <- (persona.skills || []) do %>
                <span class="text-[8px] bg-base-content/5 px-2 py-0.5 rounded-full font-bold uppercase"><%= skill %></span>
              <% end %>
            </div>
            
            <div class="card-actions justify-end mt-6">
              <a href={"/agents/#{persona.id}"} class="btn btn-xs btn-ghost gap-2">Passport <.icon name="hero-arrow-right" class="size-3" /></a>
            </div>
          </div>
        </div>
        
        <%!-- ADD NEW PLACEHOLDER --%>
        <a href="/agents/new" class="card card-bordered border-dashed bg-transparent hover:bg-base-200/50 transition-all cursor-pointer group no-underline">
          <div class="card-body p-4 items-center justify-center text-center opacity-40 group-hover:opacity-80">
            <.icon name="hero-plus-circle" class="size-8 mb-2" />
            <p class="text-xs font-bold font-mono">NEW_IDENTITY_PROMPT</p>
          </div>
        </a>
      </section>
    </div>
    """
  end
end
