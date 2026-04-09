defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer that dynamically tracks loaded modules and appends their documentation
  to `SKILL.md` using universal YAML standards (1024 char limit, properly indented block scalars).
  """
  use GenServer
  require Logger

  # Update every 5 minutes
  @interval 5 * 60 * 1000
  @skill_file "SKILL.md"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    Logger.info("GovernanceCore.Monitoring.SkillTracker started.")
    {:ok, state}
  end

  def handle_info(:update, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp update_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Filter modules that have docs and might be relevant tools/skills
        relevant_modules =
          modules
          |> Enum.filter(&String.starts_with?(inspect(&1), "GovernanceCore."))
          |> Enum.map(&extract_skill_info/1)
          |> Enum.reject(&is_nil/1)

        write_to_skill_md(relevant_modules)

      _ ->
        Logger.error("Could not retrieve modules for SkillTracker")
    end
  end

  defp extract_skill_info(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        %{
          name: inspect(mod),
          description: doc,
          version: "1.0.0"
        }

      _ ->
        nil
    end
  end

  defp write_to_skill_md(skills) do
    content =
      skills
      |> Enum.map(&format_yaml_entry/1)
      |> Enum.join("\n")

    File.write(@skill_file, content, [:write, :utf8])
    Logger.info("SkillTracker updated SKILL.md")
  end

  defp format_yaml_entry(%{name: name, description: desc, version: version}) do
    # Truncate content to enforce 1024 char limit before yaml interpolation
    truncated_desc =
      if String.length(desc) > 1024 do
        String.slice(desc, 0, 1021) <> "..."
      else
        desc
      end

    # Explicitly indent multiline string for YAML block scalar
    indented_desc =
      truncated_desc
      |> String.split("\n")
      |> Enum.map(fn line -> "  " <> line end)
      |> Enum.join("\n")

    """
    ---
    name: #{name}
    version: #{version}
    description: |
    #{indented_desc}
    ---
    """
  end
end
