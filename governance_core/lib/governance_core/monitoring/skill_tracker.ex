defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically updates SKILL.md documentation to reflect currently loaded modules.
  Enforces universal standards (1024 characters limit, YAML format).
  """
  use GenServer
  require Logger

  # Check every hour
  @interval 60 * 60 * 1000
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
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # We format as basic YAML list of modules
        # Need to chunk to ensure no file > 1024 chars
        generate_and_write_yaml(modules)
      _ ->
        Logger.error("SkillTracker: Could not load application modules")
    end
  end

  defp generate_and_write_yaml(modules) do
    base_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(base_dir)

    chunks = chunk_modules_for_yaml(modules, [], [])

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {yaml_content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      path = Path.join(base_dir, filename)

      case File.write(path, yaml_content) do
        :ok ->
          Logger.info("SkillTracker: Updated #{filename}")
        {:error, reason} ->
          Logger.error("SkillTracker: Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  # Helper to recursively build chunks of modules that fit within @max_chars when rendered as YAML
  defp chunk_modules_for_yaml([], current_chunk, acc_chunks) do
    if current_chunk == [] do
      Enum.reverse(acc_chunks)
    else
      Enum.reverse([render_yaml(current_chunk) | acc_chunks])
    end
  end

  defp chunk_modules_for_yaml([mod | rest], current_chunk, acc_chunks) do
    candidate_chunk = current_chunk ++ [mod]
    candidate_yaml = render_yaml(candidate_chunk)

    if String.length(candidate_yaml) > @max_chars do
      # If adding the module exceeds max chars, finish the current chunk and start a new one with the module
      if current_chunk == [] do
        # Edge case: a single module exceeds the limit (should rarely happen for module names)
        chunk_modules_for_yaml(rest, [], [candidate_yaml | acc_chunks])
      else
        chunk_modules_for_yaml(rest, [mod], [render_yaml(current_chunk) | acc_chunks])
      end
    else
      # Still fits, keep adding to current chunk
      chunk_modules_for_yaml(rest, candidate_chunk, acc_chunks)
    end
  end

  defp render_yaml(modules) do
    header = "skills:\n"
    items = Enum.map(modules, fn mod -> "  - #{inspect(mod)}\n" end) |> Enum.join("")
    header <> items
  end
end
