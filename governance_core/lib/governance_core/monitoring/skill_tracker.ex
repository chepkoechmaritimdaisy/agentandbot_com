defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically updates SKILL.md documentation files in the `priv/` directory,
  chunking them dynamically to ensure no file exceeds a 1024-character limit.
  """
  use GenServer
  require Logger

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
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def perform_update do
    Logger.info("Updating SKILL.md documentation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.map(&format_module_info/1)
        |> chunk_and_write()

      _ ->
        Logger.error("Failed to retrieve modules for SKILL.md generation.")
    end
  end

  defp format_module_info(module) do
    "- module: #{inspect(module)}\n"
  end

  defp chunk_and_write(items) do
    base_dir = Path.join(File.cwd!(), "priv")

    # Ensure priv exists
    File.mkdir_p!(base_dir)

    chunks = do_chunk(items, [], "", 1)

    Enum.each(chunks, fn {file_name, content} ->
      path = Path.join(base_dir, file_name)
      case File.write(path, content) do
        :ok -> Logger.info("Updated #{file_name}")
        {:error, reason} -> Logger.error("Failed to write #{file_name}: #{inspect(reason)}")
      end
    end)
  end

  defp do_chunk([], chunks, current_chunk, index) do
    if current_chunk != "" do
      file_name = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      [{file_name, current_chunk} | chunks] |> Enum.reverse()
    else
      Enum.reverse(chunks)
    end
  end

  defp do_chunk([item | rest], chunks, current_chunk, index) do
    header = if current_chunk == "", do: "skills:\n", else: ""
    proposed_chunk = current_chunk <> header <> item

    if String.length(proposed_chunk) > @char_limit do
      file_name = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"

      # Item itself might be longer than 1024, but we assume each item is short enough.
      # Start a new chunk with the item
      do_chunk(rest, [{file_name, current_chunk} | chunks], "skills:\n" <> item, index + 1)
    else
      do_chunk(rest, chunks, proposed_chunk, index)
    end
  end
end
