defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that discovers system modules and continuously generates YAML documentation
  for them, strictly enforcing a 1024-character limit per file by chunking.
  Outputs files to `priv/SKILL.md`, `priv/SKILL_2.md`, etc.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
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
    perform_tracking()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  def perform_tracking do
    Logger.debug("Starting continuous Skill Tracking...")

    # Discover modules
    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules_for_yaml(modules, [], [])
    write_chunks(chunks)

    Logger.debug("Skill Tracking complete.")
  end

  defp chunk_modules_for_yaml([], current_chunk, all_chunks) do
    if current_chunk == [], do: Enum.reverse(all_chunks), else: Enum.reverse([current_chunk | all_chunks])
  end

  defp chunk_modules_for_yaml([mod | rest], current_chunk, all_chunks) do
    new_chunk = [mod | current_chunk]
    yaml = generate_yaml(new_chunk)

    if String.length(yaml) > @max_chars do
      # If adding this module exceeds the limit, save current chunk and start a new one with this module
      chunk_modules_for_yaml(rest, [mod], [current_chunk | all_chunks])
    else
      chunk_modules_for_yaml(rest, new_chunk, all_chunks)
    end
  end

  defp generate_yaml(modules) do
    # Simple YAML representation
    header = "skills:\n"
    body = Enum.map_join(modules, "\n", fn mod -> "  - name: #{inspect(mod)}" end)
    header <> body <> "\n"
  end

  defp write_chunks(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks, fn chunk, index ->
      suffix = if index == 0, do: "", else: "_#{index + 1}"
      filename = "SKILL#{suffix}.md"
      filepath = Path.join(priv_dir, filename)

      yaml_content = generate_yaml(Enum.reverse(chunk))

      case File.write(filepath, yaml_content) do
        :ok ->
          Logger.debug("Successfully wrote #{filepath}")
        {:error, reason} ->
          Logger.error("Failed to write #{filepath}: #{inspect(reason)}")
      end
    end)
  end
end
