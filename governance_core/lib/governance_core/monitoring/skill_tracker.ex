defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that runs continuously (every 5 minutes) to monitor available
  functions and modules, and update the SKILL.md documentation in YAML format.
  Enforces a 1024-character limit per file by chunking into multiple files.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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
    Logger.info("Starting SKILL.md Standardization Update...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Just grab the names of the modules as strings for our simplified docs
        module_names = Enum.map(modules, &to_string/1)

        chunks = chunk_for_yaml(module_names, 1024, [], [])

        write_chunks(chunks, 1)

      :undefined ->
        Logger.error("Failed to fetch modules for SKILL.md generation")
    end
  end

  # Helper to recursively chunk the data to ensure the YAML output doesn't exceed `max_len`
  defp chunk_for_yaml([], _max_len, current_chunk, all_chunks) do
    if Enum.empty?(current_chunk) do
      Enum.reverse(all_chunks)
    else
      Enum.reverse([Enum.reverse(current_chunk) | all_chunks])
    end
  end

  defp chunk_for_yaml([item | rest], max_len, current_chunk, all_chunks) do
    # Calculate the size of what the YAML would be with the new item added
    test_chunk = [item | current_chunk]
    test_yaml = to_yaml(Enum.reverse(test_chunk))

    if String.length(test_yaml) > max_len and not Enum.empty?(current_chunk) do
      # If adding this item pushes us over the limit, finalize the current chunk and start a new one
      chunk_for_yaml(rest, max_len, [item], [Enum.reverse(current_chunk) | all_chunks])
    else
      # Otherwise, keep adding to the current chunk
      chunk_for_yaml(rest, max_len, test_chunk, all_chunks)
    end
  end

  defp to_yaml(items) do
    """
    skills:
    """ <> Enum.map_join(items, "\n", fn item -> "  - #{item}" end) <> "\n"
  end

  defp write_chunks([], _index), do: :ok
  defp write_chunks([chunk | rest], index) do
    filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
    file_path = Path.join(File.cwd!(), "priv/#{filename}")

    yaml_content = to_yaml(chunk)

    case File.write(file_path, yaml_content) do
      :ok -> Logger.info("Updated #{filename}")
      {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
    end

    write_chunks(rest, index + 1)
  end
end
