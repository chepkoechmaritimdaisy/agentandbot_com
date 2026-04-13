defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that dynamically manages SKILL.md tool documentation by
  discovering modules and maintaining universal standards like YAML and a 1024 char limit.
  """
  use GenServer
  require Logger

  # Update every 6 hours
  @interval 6 * 60 * 60 * 1000
  @max_chars 1024

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
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp update_skills do
    Logger.info("Updating SKILL.md...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Just generating a sample content based on modules for this example
        module_list =
          modules
          |> Enum.map(&to_string/1)
          |> Enum.join("\n    - ")

        content = "modules:\n    - #{module_list}"

        # Truncate content to max 1024 chars on a newline to avoid breaking YAML
        truncated_content = truncate_content(content, @max_chars)

        yaml_content = """
        version: 1.0
        project: GovernanceCore
        description: |
          Auto-generated module tracking document.
        details: |
          #{String.replace(truncated_content, "\n", "\n  ")}
        """

        skill_file_path = Path.join(:code.priv_dir(:governance_core), "SKILL.md")
        File.write!(skill_file_path, yaml_content)
        Logger.info("Successfully updated #{skill_file_path}")

      :undefined ->
        Logger.warning("Could not retrieve modules for governance_core")
    end
  end

  defp truncate_content(content, max_length) do
    if String.length(content) > max_length do
      content
      |> String.slice(0, max_length)
      # Truncate at the last complete newline to ensure we don't break in the middle of a word/line
      |> String.replace(~r/\n[^\n]*$/, "")
    else
      content
    end
  end
end
