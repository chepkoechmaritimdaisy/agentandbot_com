defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically generates and updates SKILL.md files for discovered tools/modules.
  Runs every 5 minutes.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_track()
    {:ok, state}
  end

  def handle_info(:track, state) do
    perform_tracking()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  def perform_tracking do
    Logger.info("Starting Skill Tracker...")

    # Discover modules
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Find some modules to document (for example purposes, all modules)
        Enum.each(modules, &document_module/1)
      _ ->
        Logger.error("Failed to get modules for governance_core")
    end

    Logger.info("Skill Tracker completed.")
  end

  defp document_module(module) do
    mod_name = inspect(module)

    # Generate content
    content = """
    name: #{mod_name}
    description: |
      Automatically generated documentation for #{mod_name}.
    status: active
    """

    # Enforce 1024-character limit by truncating at the last complete newline
    truncated_content = if String.length(content) > 1024 do
      content
      |> String.slice(0, 1024)
      |> String.replace(~r/\n[^\n]*$/, "")
    else
      content
    end

    # Write dynamically to priv directory
    priv_dir = :code.priv_dir(:governance_core)

    if is_list(priv_dir) or is_binary(priv_dir) do
      priv_dir_path = to_string(priv_dir)
      # Create skills dir if not exists
      skills_dir = Path.join(priv_dir_path, "skills")
      File.mkdir_p!(skills_dir)

      file_path = Path.join(skills_dir, "#{mod_name}_SKILL.md")
      File.write(file_path, truncated_content)
    end
  end
end
