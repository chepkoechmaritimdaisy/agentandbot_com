defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates and updates SKILL.md documentation based on discovered modules,
  ensuring 1024-character limits and generating multiple chunks if needed.
  """
  use GenServer
  require Logger

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

  defp perform_update do
    Logger.info("Starting SkillTracker update...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules(modules, [], "")

    Enum.with_index(chunks, fn content, index ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      file_path = Path.join([File.cwd!(), "priv", filename])

      case File.write(file_path, content) do
        :ok -> Logger.info("Wrote #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_modules([], chunks, current_chunk) do
    if current_chunk == "", do: chunks, else: chunks ++ [current_chunk]
  end

  defp chunk_modules([mod | rest], chunks, current_chunk) do
    item = "- #{inspect(mod)}\n"

    if String.length(current_chunk) + String.length(item) > 1024 do
      chunk_modules(rest, chunks ++ [current_chunk], item)
    else
      chunk_modules(rest, chunks, current_chunk <> item)
    end
  end
end
