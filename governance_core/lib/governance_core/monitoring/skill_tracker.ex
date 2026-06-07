defmodule GovernanceCore.Monitoring.SkillTracker do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @max_chars 1024

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

  def perform_track do
    Logger.info("Starting SkillTracker...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        module_names = Enum.map(modules, &to_string/1) |> Enum.sort()
        write_yaml_chunks(module_names)
      _ ->
        Logger.warning("Failed to fetch modules for SkillTracker.")
    end
  end

  defp write_yaml_chunks(modules) do
    chunks = chunk_for_yaml(modules, [], [])

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join([File.cwd!(), "priv", filename])

      content = generate_yaml(chunk)
      case File.write(file_path, content) do
        :ok -> Logger.info("Wrote #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_for_yaml([], current_chunk, all_chunks) do
    Enum.reverse([Enum.reverse(current_chunk) | all_chunks]) |> Enum.reject(&Enum.empty?/1)
  end

  defp chunk_for_yaml([mod | rest], current_chunk, all_chunks) do
    test_chunk = [mod | current_chunk]
    yaml = generate_yaml(Enum.reverse(test_chunk))

    if String.length(yaml) > @max_chars do
      # If current chunk alone is empty, force include to avoid infinite loop
      if Enum.empty?(current_chunk) do
        chunk_for_yaml(rest, [], [[mod] | all_chunks])
      else
        chunk_for_yaml([mod | rest], [], [Enum.reverse(current_chunk) | all_chunks])
      end
    else
      chunk_for_yaml(rest, test_chunk, all_chunks)
    end
  end

  defp generate_yaml(modules) do
    """
    tools:
    #{Enum.map(modules, fn m -> "  - name: #{m}" end) |> Enum.join("\n")}
    """
  end
end
