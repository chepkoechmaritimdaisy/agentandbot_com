defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Dynamically tracks capabilities and tools within the application and writes
  them to SKILL.md in standard YAML format. Strictly enforces a 1024-character
  limit per file by chunking.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_track()
    {:ok, state}
  end

  def handle_info(:track, state) do
    perform_track()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  defp perform_track do
    Logger.debug("SkillTracker: Starting module tracking...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        # filter out standard elixirc/phoenix modules for brevity, just tracking top-level
        |> Enum.map(&to_string/1)
        |> Enum.filter(&String.starts_with?(&1, "Elixir.GovernanceCore"))
        |> chunk_and_write_yaml()

      :undefined ->
        Logger.error("SkillTracker: Could not get modules for governance_core")
    end
  end

  defp chunk_and_write_yaml(module_strings) do
    base_path = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(base_path)

    chunked = chunk_by_size(module_strings, 1024, [], [])

    chunked
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(base_path, filename)
      yaml_content = generate_yaml(chunk)

      case File.write(file_path, yaml_content) do
        :ok -> Logger.debug("SkillTracker: Wrote #{filename}")
        {:error, reason} -> Logger.error("SkillTracker: Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_by_size([], _max_size, current_chunk, all_chunks) do
    Enum.reverse([Enum.reverse(current_chunk) | all_chunks])
  end

  defp chunk_by_size([item | rest], max_size, current_chunk, all_chunks) do
    test_chunk = [item | current_chunk] |> Enum.reverse()
    test_yaml = generate_yaml(test_chunk)

    if String.length(test_yaml) > max_size and current_chunk != [] do
      chunk_by_size(rest, max_size, [item], [Enum.reverse(current_chunk) | all_chunks])
    else
      chunk_by_size(rest, max_size, [item | current_chunk], all_chunks)
    end
  end

  defp generate_yaml(modules) do
    yaml_lines = ["---", "capabilities:"] ++ Enum.map(modules, fn m -> "  - #{m}" end)
    Enum.join(yaml_lines, "\n") <> "\n"
  end
end
