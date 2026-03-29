defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically checks for new Elixir functions and updates SKILL.md
  with YAML frontmatter, enforcing a 1024-character limit per entry.
  """
  use GenServer
  require Logger

  # 1 hour in milliseconds
  @interval 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update, state) do
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def perform_update do
    Logger.info("Starting SkillTracker update for SKILL.md...")

    # Find modules starting with Elixir.GovernanceCore
    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, app_modules} ->
          app_modules
          |> Enum.filter(fn mod -> String.starts_with?(to_string(mod), "Elixir.GovernanceCore") end)
        :undefined ->
          Logger.warning("SkillTracker could not get modules for :governance_core application")
          []
      end

    skills = Enum.flat_map(modules, &extract_skills/1)

    yaml_content = Enum.map_join(skills, "\n---\n", &format_skill/1)

    File.write!("SKILL.md", yaml_content)
    Logger.info("SkillTracker updated SKILL.md successfully.")
  end

  defp extract_skills(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _anno, _lang, _format, _mod_doc, _meta, docs} ->
        Enum.map(docs, fn
          {{:function, name, arity}, _anno, _signatures, %{"en" => doc}, _meta} ->
            %{name: "#{module}.#{name}/#{arity}", description: doc}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      {:error, _} -> []
    end
  end

  defp format_skill(%{name: name, description: description}) do
    # Truncate to 1024 characters before interpolating to avoid breaking YAML structure
    description = String.slice(description, 0..1023)

    # Indent description for YAML block scalar
    indented_desc = String.replace(description, "\n", "\n  ")

    """
    name: #{name}
    description: |
      #{indented_desc}
    """
  end
end
