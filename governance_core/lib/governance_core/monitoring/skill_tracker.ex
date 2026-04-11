defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically discovers tools and functions in the system and generates
  standardized YAML documentation in SKILL.md.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_track()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:track, state) do
    generate_skill_doc()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  defp generate_skill_doc do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        content = modules
          |> Enum.map(&to_string/1)
          |> Enum.sort()
          |> Enum.join("\n")

        # Bound to 1024 chars and truncate at last newline
        content =
          if String.length(content) > 1000 do # leave room for indentation and YAML structure
            content
            |> String.slice(0, 1000)
            |> String.replace(~r/\n[^\n]*$/, "")
          else
            content
          end

        # Indent multiline strings for YAML block scalar
        indented_content =
          content
          |> String.split("\n")
          |> Enum.map(fn line -> "    " <> line end)
          |> Enum.join("\n")

        yaml = """
        skills:
          modules: |
        #{indented_content}
        """

        file_path = Path.join(:code.priv_dir(:governance_core), "SKILL.md")
        File.write!(file_path, yaml)
        Logger.info("SkillTracker updated SKILL.md")

      :undefined ->
        Logger.warning("SkillTracker could not load modules")
    end
  end
end
