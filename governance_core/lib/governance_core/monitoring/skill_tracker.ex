defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Generates `SKILL.md` files dynamically from the project's modules.
  Enforces a strict 1024-character limit per file by chunking data.
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

  def perform_update do
    Logger.info("Starting SkillTracker Update...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        chunk_and_write_modules(modules)
      _ ->
        Logger.error("Failed to retrieve modules for :governance_core")
    end
  end

  defp chunk_and_write_modules(modules) do
    chunks = build_yaml_chunks(modules, [], "")

    dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(dir)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {yaml_content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(dir, filename)

      case File.write(file_path, yaml_content) do
        :ok ->
          Logger.info("Successfully wrote #{filename}")
        {:error, reason} ->
          Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp build_yaml_chunks([], completed_chunks, current_chunk) do
    if current_chunk == "" do
      Enum.reverse(completed_chunks)
    else
      Enum.reverse([current_chunk | completed_chunks])
    end
  end

  defp build_yaml_chunks([module | rest], completed_chunks, current_chunk) do
    mod_name = inspect(module)
    entry = "- module: #{mod_name}\n"

    new_chunk =
      if current_chunk == "" do
        "modules:\n" <> entry
      else
        current_chunk <> entry
      end

    if String.length(new_chunk) > 1024 do
      # If current chunk was empty, we have a single entry > 1024 chars (unlikely).
      if current_chunk == "" do
        build_yaml_chunks(rest, [new_chunk | completed_chunks], "")
      else
        build_yaml_chunks([module | rest], [current_chunk | completed_chunks], "")
      end
    else
      build_yaml_chunks(rest, completed_chunks, new_chunk)
    end
  end
end
