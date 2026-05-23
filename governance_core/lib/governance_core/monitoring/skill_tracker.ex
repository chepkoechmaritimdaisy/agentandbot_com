defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that periodically discovers modules in the application and
  generates YAML documentation (SKILL.md) ensuring file size constraints.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
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
  def handle_info(:update_skills, state) do
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp perform_update do
    Logger.info("Updating SKILL.md...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        yaml_entries = Enum.map(modules, fn mod -> "- module: #{inspect(mod)}\n" end)
        chunks = chunk_entries(yaml_entries, [], [])

        Enum.with_index(chunks, fn chunk, index ->
          content = "skills:\n" <> Enum.join(chunk)
          filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
          filepath = Path.join(File.cwd!(), "priv/#{filename}")

          case File.write(filepath, content) do
            :ok -> Logger.info("Wrote #{filepath}")
            {:error, reason} -> Logger.error("Failed to write #{filepath}: #{inspect(reason)}")
          end
        end)
      :undefined ->
        Logger.error("Failed to get modules for governance_core")
    end
  end

  # Dynamically chunks entries ensuring each chunk (with "skills:\n" header) stays within @max_chars
  defp chunk_entries([], current_chunk, all_chunks) do
    if current_chunk == [], do: Enum.reverse(all_chunks), else: Enum.reverse([Enum.reverse(current_chunk) | all_chunks])
  end

  defp chunk_entries([entry | rest], current_chunk, all_chunks) do
    # Length of "skills:\n" is 8 characters
    current_length = 8 + Enum.reduce(current_chunk, 0, fn c, acc -> acc + String.length(c) end)
    entry_length = String.length(entry)

    if current_length + entry_length > @max_chars do
      chunk_entries(rest, [entry], [Enum.reverse(current_chunk) | all_chunks])
    else
      chunk_entries(rest, [entry | current_chunk], all_chunks)
    end
  end
end
