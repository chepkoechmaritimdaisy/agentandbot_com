defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that standardizes and updates SKILL.md documentation for the project.
  Runs every 5 minutes, formatting documentation into YAML format.
  """

  use GenServer
  require Logger

  @interval 5 * 60 * 1000
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
  def handle_info(:update, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp update_skills do
    Logger.debug("Updating SKILL.md...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Just creating some dummy formatted content to represent tool skills
        content = "Tools available:\n" <> Enum.map_join(Enum.take(modules, 10), "\n", &"  - #{inspect(&1)}")

        # Enforce 1024 char limit and truncate at last newline
        truncated_content =
          if String.length(content) > @max_chars do
            content
            |> String.slice(0, @max_chars)
            |> String.replace(~r/\n[^\n]*$/, "")
          else
            content
          end

        # Format as YAML block scalar
        yaml_content = "skills: |\n" <> Enum.map_join(String.split(truncated_content, "\n"), "\n", &"  #{&1}") <> "\n"

        priv_dir = :code.priv_dir(:governance_core)
        file_path = Path.join(priv_dir, "SKILL.md")

        case File.write(file_path, yaml_content) do
          :ok -> Logger.debug("Successfully updated SKILL.md")
          {:error, reason} -> Logger.error("Failed to write SKILL.md: #{inspect(reason)}")
        end

      _ ->
        Logger.error("Failed to fetch modules for SkillTracker")
    end
  end
end
