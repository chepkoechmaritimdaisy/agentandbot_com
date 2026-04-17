defmodule GovernanceCore.Monitoring.SkillTracker do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes
  @max_chars 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(state) do
    schedule_track()
    {:ok, state}
  end

  def handle_info(:track, state) do
    track()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  defp track do
    {:ok, modules} = :application.get_key(:governance_core, :modules)

    modules_text = Enum.join(modules, "\n")
    truncated_text = if String.length(modules_text) > @max_chars do
      # Truncate to 1024 chars, breaking at last complete newline
      String.slice(modules_text, 0, @max_chars)
      |> String.replace(~r/\n[^\n]*$/, "")
    else
      modules_text
    end

    # Indent for YAML block scalar
    indented_text =
      truncated_text
      |> String.split("\n")
      |> Enum.map(fn line -> "  #{line}" end)
      |> Enum.join("\n")

    yaml_content = """
    skills:
      - name: System Modules
        description: |
    #{indented_text}
    """

    priv_dir = :code.priv_dir(:governance_core)
    filepath = Path.join(priv_dir, "SKILL.md")

    File.write!(filepath, yaml_content)
    Logger.info("SkillTracker updated #{filepath}")
  end
end
