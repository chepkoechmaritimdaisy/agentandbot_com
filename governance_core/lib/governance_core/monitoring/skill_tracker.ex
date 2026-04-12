defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks and documents new tools or functions by generating
  standardized SKILL.md files in the application's priv directory.
  """
  use GenServer
  require Logger

  # Run every hour
  @interval 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_update()
    {:ok, state}
  end

  @impl true
  def handle_info(:update_skills, state) do
    update_skill_docs()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  def update_skill_docs do
    Logger.info("Starting SkillTracker to generate SKILL.md documents...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Just grab a few interesting ones as an example, or all of them.
        modules
        |> Enum.filter(&is_governance_module?/1)
        |> Enum.each(&process_module/1)

      :undefined ->
        Logger.error("Failed to fetch modules for governance_core")
    end
  end

  defp is_governance_module?(module) do
    String.starts_with?(to_string(module), "Elixir.GovernanceCore.")
  end

  defp process_module(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        write_skill_md(module, doc)
      _ ->
        # No docs or unable to fetch
        :ok
    end
  end

  defp write_skill_md(module, doc) do
    # Truncate documentation to 1024 chars at the last newline
    truncated_doc =
      doc
      |> String.slice(0, 1024)
      |> String.replace(~r/\n[^\n]*$/, "")

    # Format as YAML block scalar (indent properly)
    yaml_doc =
      truncated_doc
      |> String.split("\n")
      |> Enum.map(fn line -> "  " <> line end)
      |> Enum.join("\n")

    yaml_content = """
    name: #{inspect(module)}
    description: |
    #{yaml_doc}
    type: tool
    """

    filename = "#{inspect(module)}_SKILL.md"
    priv_dir = :code.priv_dir(:governance_core)
    path = Path.join([priv_dir, filename])

    File.write!(path, yaml_content)
    Logger.info("SkillTracker updated #{filename}")
  end
end
