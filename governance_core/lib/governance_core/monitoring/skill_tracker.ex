defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that continuously standardizes and generates SKILL.md for tools/modules
  within the project. It enforces a 1024-character limit and writes output in YAML format.
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

  defp perform_tracking do
    Logger.debug("Starting SkillTracker cycle...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules_content =
          modules
          |> Enum.map(&to_string/1)
          |> Enum.join("\n")

        # Truncate content to 1024 characters max at the last complete newline
        truncated_content = truncate_content(modules_content, 1000) # leave room for formatting

        # Explicitly indent line-by-line for YAML block scalar
        indented_content =
          truncated_content
          |> String.split("\n")
          |> Enum.map(fn line -> "  " <> line end)
          |> Enum.join("\n")

        yaml_output = """
        name: GovernanceCore Skills
        version: 1.0
        description: Auto-generated list of modules
        modules: |
        #{indented_content}
        """

        file_path = Path.join(:code.priv_dir(:governance_core), "SKILL.md")
        File.write!(file_path, yaml_output)
        Logger.info("SkillTracker generated SKILL.md at #{file_path}")

      :undefined ->
        Logger.warning("SkillTracker: Could not get modules for :governance_core")
    end
  end

  defp truncate_content(content, limit) do
    if String.length(content) > limit do
      sliced = String.slice(content, 0, limit)
      String.replace(sliced, ~r/\n[^\n]*$/, "")
    else
      content
    end
  end
end
