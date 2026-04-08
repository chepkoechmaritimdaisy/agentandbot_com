defmodule GovernanceCoreWeb.ScenarioBoardLive do
  use GovernanceCoreWeb, :live_view

  def mount(_params, _session, socket) do
    # MOCK DATA: Hybrid Collaboration Scenario (Script Writing)
    scenarios = [
      %{
        id: "s1",
        name: "YouTube Script Writer v2",
        entity: "YouTube Hub",
        status: "active",
        progress: 65,
        tasks: [
          %{id: "t1", title: "Generate Draft", stage: "done", assignee: "Creative Writer (Bot)"},
          %{id: "t2", title: "Fact Check", stage: "in_progress", assignee: "Jules Monitoring (Bot)"},
          %{id: "t3", title: "Human Review & Edit", stage: "todo", assignee: "İlker İpçioğlu (Human)"}
        ]
      },
      %{
        id: "s2",
        name: "E-commerce Inventory Audit",
        entity: "eny.com.tr",
        status: "active",
        progress: 20,
        tasks: [
          %{id: "t4", title: "Fetch SKU Data", stage: "done", assignee: "eny.com.tr Bot"},
          %{id: "t5", title: "Cross-check with Warehouse", stage: "in_progress", assignee: "DataScraper Pro (Bot)"}
        ]
      }
    ]

    {:ok, assign(socket, scenarios: scenarios)}
  end

  def render(assigns) do
    ~H"""
    <div id="scenario-hub" class="space-y-10">
      <%!-- ACTIVE SCENARIOS LIST --%>
      <section :for={scenario <- @scenarios} class="p-6 rounded-2xl bg-base-200 border border-base-content/5 space-y-6">
        <header class="flex items-center justify-between">
          <div>
            <div class="flex items-center gap-2 mb-1">
              <span class="badge badge-sm badge-outline opacity-50 uppercase text-[10px]">{scenario.entity}</span>
              <span class="badge badge-sm badge-success uppercase text-[10px] font-bold">{scenario.status}</span>
            </div>
            <h3 class="text-xl font-black">{scenario.name}</h3>
          </div>
          <div class="text-right">
            <div class="radial-progress text-primary" style={"--value:#{scenario.progress}; --size:3rem; --thickness: 4px;"} role="progressbar">
              <span class="text-[10px] font-bold">{scenario.progress}%</span>
            </div>
          </div>
        </header>

        <%!-- KANBAN BOARD (Mini) --%>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div :for={stage <- ["todo", "in_progress", "done"]} class="flex flex-col gap-3">
            <h4 class="text-[10px] font-bold uppercase opacity-30 px-2 tracking-widest">{stage}</h4>
            <div class="space-y-2">
              <div 
                :for={task <- Enum.filter(scenario.tasks, &(&1.stage == stage))}
                class="p-3 rounded-lg bg-base-100 border border-base-content/5 shadow-sm hover:border-primary/30 transition-all flex flex-col gap-2"
              >
                <p class="text-xs font-bold leading-tight">{task.title}</p>
                <div class="flex items-center gap-2 mt-1">
                   <div class="avatar placeholder">
                    <div class="bg-neutral text-neutral-content w-4 rounded-full">
                      <span class="text-[8px]">{String.at(task.assignee, 0)}</span>
                    </div>
                  </div>
                  <span class="text-[10px] opacity-50 truncate">{task.assignee}</span>
                </div>
              </div>
            </div>
            
            <%!-- EMPTY STATE / CTA --%>
            <button :if={stage == "todo"} class="btn btn-sm btn-ghost border-dashed border-base-content/10 text-[10px]">
              + New Task (Drafting...)
            </button>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
