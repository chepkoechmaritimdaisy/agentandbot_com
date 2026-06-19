defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically generates and updates SKILL.md documentation
  based on the application's available modules, ensuring an
  universal standard (YAML format, max 1024 chars per file).
  """
  use GenServer
  require Logger

  # Update interval: 1 hour
  @interval 60 * 60 * 1000
  @max_chars 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update, state) do
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def perform_update do
    Logger.info("SkillTracker: Updating SKILL.md documentation...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    formatted_skills = Enum.map(modules, fn mod ->
      "- module: #{inspect(mod)}\n  description: Auto-generated entry.\n"
    end)

    chunks = chunk_by_length(formatted_skills, @max_chars, [], "")

    base_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(base_dir)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(base_dir, filename)

      yaml_content = """
      ---
      type: skill_manifest
      part: #{index}
      ---
      skills:
      #{content}
      """

      File.write!(filepath, yaml_content)
    end)

    Logger.info("SkillTracker: Documentation updated across #{length(chunks)} file(s).")
  end

  # Helper to group strings such that the total length of the concatenated group
  # does not exceed the max_chars limit (including YAML headers roughly).
  defp chunk_by_length([], _max, acc_chunks, current_chunk) do
    if current_chunk == "", do: Enum.reverse(acc_chunks), else: Enum.reverse([current_chunk | acc_chunks])
  end

  defp chunk_by_length([item | rest], max, acc_chunks, current_chunk) do
    new_chunk = current_chunk <> item
    # Rough estimate of YAML header size is ~50 chars
    if String.length(new_chunk) + 50 > max do
      if current_chunk == "" do
        # Item is too big on its own, force it
        chunk_by_length(rest, max, [item | acc_chunks], "")
      else
        chunk_by_length([item | rest], max, [current_chunk | acc_chunks], "")
      end
    else
      chunk_by_length(rest, max, acc_chunks, new_chunk)
    end
  end
end
