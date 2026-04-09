defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that dynamically manages tool documentation (`SKILL.md`).
  It generates a YAML formatted file containing all modules in the application
  and ensures it meets the 1024-character limit standard.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # Run every hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
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
        # Generate the list of modules, formatting them as a string
        module_list =
          modules
          |> Enum.map(&to_string/1)
          |> Enum.join("\n  ")

        # Create the content first, then truncate to avoid breaking YAML
        content = "  " <> module_list

        # Truncate content to 1024 chars minus the size of the YAML wrapper
        max_content_length = 1024 - String.length("---\nskills: |\n...\n")
        truncated_content =
          if String.length(content) > max_content_length do
            content
            |> String.slice(0, max_content_length)
            |> String.replace(~r/\n[^\n]*$/, "") # Truncate at the last complete newline
          else
            content
          end

        # YAML format with explicit indentation for block scalars
        yaml = """
        ---
        skills: |
        #{truncated_content}
        ...
        """

        path = Path.join(:code.priv_dir(:governance_core), "SKILL.md")

        case File.write(path, yaml) do
          :ok -> Logger.info("Successfully updated SKILL.md")
          {:error, reason} -> Logger.error("Failed to write SKILL.md: #{inspect(reason)}")
        end

      :undefined ->
        Logger.error("Failed to retrieve modules for SKILL.md update")
    end
  end
end
