defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Monitors newly added modules/tools and automatically generates or updates SKILL.md
  to ensure universal standard compliance (YAML format, 1024 char limits).
  """
  use GenServer
  require Logger

  @interval 12 * 60 * 60 * 1000 # 12 hours

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def perform_check do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules_str =
          modules
          |> Enum.map(&to_string/1)
          |> Enum.join("\n")

        # Truncate at last complete newline to respect 1024 char limit
        truncated_str =
          if String.length(modules_str) > 1024 do
            sliced = String.slice(modules_str, 0, 1024)
            String.replace(sliced, ~r/\n[^\n]*$/, "")
          else
            modules_str
          end

        # Indent line by line for YAML block scalar
        indented_str =
          truncated_str
          |> String.split("\n")
          |> Enum.map(fn line -> "      " <> line end)
          |> Enum.join("\n")

        yaml_content = """
        tools:
          - name: GovernanceCore Modules
            description: |
        #{indented_str}
        """

        file_path = Path.join(:code.priv_dir(:governance_core), "SKILL.md")
        try do
          File.write!(file_path, yaml_content)
          Logger.info("SkillTracker updated SKILL.md at #{file_path}")
        rescue
          e -> Logger.warning("SkillTracker: Failed to write SKILL.md to #{file_path} - #{inspect(e)}")
        end

      :undefined ->
        Logger.warning("SkillTracker: Could not get modules for application")
    end
  end
end
