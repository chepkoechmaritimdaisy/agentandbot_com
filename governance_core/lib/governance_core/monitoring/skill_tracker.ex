defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates and updates SKILL.md documentation in the project's source priv/ directory,
  ensuring files comply with the 1024-character size limit by dynamically chunking
  YAML outputs across multiple files.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour
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

  def update_skills do
    Logger.info("Starting Skill Tracker update...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    docs =
      modules
      |> Enum.map(fn mod ->
        # Simple extraction of module name as a proxy for skill/tool
        name = to_string(mod)
        "  - name: #{name}\n    type: module"
      end)

    chunked_docs = chunk_by_length(docs, @max_chars, "skills:\n", [])

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    chunked_docs
    |> Enum.with_index()
    |> Enum.each(fn {content, index} ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      filepath = Path.join(priv_dir, filename)
      File.write!(filepath, content)
    end)

    Logger.info("Skill Tracker successfully updated #{length(chunked_docs)} SKILL.md files in #{priv_dir}")
  end

  defp chunk_by_length([], _max, current_chunk, acc) do
    Enum.reverse([current_chunk | acc])
  end

  defp chunk_by_length([doc | rest], max, current_chunk, acc) do
    new_chunk = current_chunk <> "\n" <> doc
    if String.length(new_chunk) > max do
      chunk_by_length(rest, max, "skills:\n" <> doc, [current_chunk | acc])
    else
      chunk_by_length(rest, max, new_chunk, acc)
    end
  end
end
