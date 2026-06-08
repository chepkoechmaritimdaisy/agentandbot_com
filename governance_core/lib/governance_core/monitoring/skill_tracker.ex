defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically updates SKILL.md files to document available modules and tools.
  Follows the standard: 1024 character limit per file, YAML format.
  """
  use GenServer
  require Logger

  # Continuous interval
  @interval 5 * 60 * 1000
  @char_limit 1024

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

  defp update_skills do
    Logger.info("Updating SKILL.md documents...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Generate raw text strings for each module
        module_entries = Enum.map(modules, fn mod ->
          "- #{inspect(mod)}\n"
        end)

        # Chunk logic based on character count of the generated YAML text
        chunks = chunk_entries(module_entries, [], [], 0)

        base_dir = Path.join(File.cwd!(), "priv")
        File.mkdir_p!(base_dir)

        chunks
        |> Enum.with_index(1)
        |> Enum.each(fn {chunk, index} ->
          filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
          path = Path.join(base_dir, filename)

          content = """
          ---
          # Auto-generated SKILL documentation
          format: yaml
          part: #{index}
          ---
          modules:
          #{Enum.join(chunk)}
          """

          case File.write(path, content) do
            :ok -> Logger.info("Wrote #{filename}")
            {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
          end
        end)

      _ ->
        Logger.error("Failed to discover modules for SKILL.md update")
    end
  end

  # Acc: [current_chunk_entries], Chunks: [list_of_chunks], Current_Len: length of current chunk string
  defp chunk_entries([], current_chunk, chunks, _current_len) do
    Enum.reverse([Enum.reverse(current_chunk) | chunks])
  end

  defp chunk_entries([entry | rest], current_chunk, chunks, current_len) do
    entry_len = String.length(entry)
    # Estimate the length of the YAML wrapper (around 100 chars)
    wrapper_len = 100

    if current_len + entry_len + wrapper_len > @char_limit and current_chunk != [] do
      # Finish current chunk, start a new one
      chunk_entries(rest, [entry], [Enum.reverse(current_chunk) | chunks], entry_len)
    else
      # Add to current chunk
      chunk_entries(rest, [entry | current_chunk], chunks, current_len + entry_len)
    end
  end
end
