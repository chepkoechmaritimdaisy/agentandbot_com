defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically updates SKILL.md files to document available project modules according to the 1024-character YAML standard.
  """

  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

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

  def update_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # We need to document these in YAML format, max 1024 chars per file.
        # We'll use a dynamic chunking approach.
        chunks = chunk_modules(modules, [], [])
        write_chunks(chunks, 1)
      _ ->
        Logger.error("Failed to retrieve application modules for SKILL.md update.")
    end
  end

  defp chunk_modules([], current_chunk, all_chunks) do
    if current_chunk == [] do
      all_chunks
    else
      [Enum.reverse(current_chunk) | all_chunks] |> Enum.reverse()
    end
  end

  defp chunk_modules([module | rest], current_chunk, all_chunks) do
    test_chunk = [module | current_chunk]
    yaml = to_yaml(Enum.reverse(test_chunk))

    if String.length(yaml) > 1024 do
      if current_chunk == [] do
        # A single module is > 1024 chars, have to put it in its own chunk anyway
        chunk_modules(rest, [], [[module] | all_chunks])
      else
        chunk_modules([module | rest], [], [Enum.reverse(current_chunk) | all_chunks])
      end
    else
      chunk_modules(rest, test_chunk, all_chunks)
    end
  end

  defp to_yaml(modules) do
    header = "---\nskills:\n"
    body = Enum.map_join(modules, "", fn mod -> "  - #{inspect(mod)}\n" end)
    header <> body
  end

  defp write_chunks([], _index), do: :ok
  defp write_chunks([chunk | rest], index) do
    filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
    filepath = Path.join([File.cwd!(), "priv", filename])

    yaml_content = to_yaml(chunk)

    case File.write(filepath, yaml_content) do
      :ok -> Logger.info("Updated #{filename}")
      {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
    end

    write_chunks(rest, index + 1)
  end
end
