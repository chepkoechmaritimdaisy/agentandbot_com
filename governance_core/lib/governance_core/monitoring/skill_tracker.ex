defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer that dynamically manages SKILL.md documentation for tools/modules
  within the application, ensuring it adheres to standards (YAML, 1024 char limits).
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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
    Logger.info("Updating SKILL.md...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    content = generate_yaml_content(modules)

    # Enforce 1024 char limit and truncate at last complete newline
    content =
      if String.length(content) > 1024 do
        String.slice(content, 0, 1024) |> String.replace(~r/\n[^\n]*$/, "")
      else
        content
      end

    path = Path.join(:code.priv_dir(:governance_core), "SKILL.md")

    case File.write(path, content) do
      :ok -> Logger.info("Successfully updated SKILL.md at #{path}")
      {:error, reason} -> Logger.error("Failed to write SKILL.md: #{inspect(reason)}")
    end

    schedule_update()
    {:noreply, state}
  end

  defp generate_yaml_content(modules) do
    modules_str = Enum.map_join(modules, "\n  ", fn mod -> "- #{inspect(mod)}" end)

    """
    version: 1.0
    modules: |
      #{modules_str}
    """
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end
end
