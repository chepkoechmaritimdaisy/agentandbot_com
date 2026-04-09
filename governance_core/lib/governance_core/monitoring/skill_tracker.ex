defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically updates SKILL.md dynamically by scanning the project's modules.
  Writes a YAML formatted string (max 1024 chars) to the application's priv directory.
  """
  use GenServer
  require Logger

  @update_interval 300_000 # 5 minutes

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_update()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:update_skills, state) do
    do_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @update_interval)
  end

  defp do_update do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules_string =
          modules
          |> Enum.map(&to_string/1)
          |> Enum.join("\n")

        # Properly indent the modules string for YAML block scalar formatting
        indented_modules =
          modules_string
          |> String.split("\n")
          |> Enum.map(fn line -> "  " <> line end)
          |> Enum.join("\n")

        yaml_content = """
        skills:
          modules: |
        #{indented_modules}
        """

        # Truncate at the last complete newline within 1024 characters
        truncated_content =
          if String.length(yaml_content) > 1024 do
            yaml_content
            |> String.slice(0, 1024)
            |> String.replace(~r/\n[^\n]*$/, "")
            |> Kernel.<>("\n")
          else
            yaml_content
          end

        # Write to priv directory
        priv_dir = :code.priv_dir(:governance_core)
        file_path = Path.join(priv_dir, "SKILL.md")
        File.write!(file_path, truncated_content)
        Logger.info("SkillTracker: Updated SKILL.md")

      _ ->
        Logger.warning("SkillTracker: Could not get modules from application")
    end
  end
end
