defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  SkillTracker GenServer.
  Dynamically manages SKILL.md tool documentation based on application modules.
  Enforces a 1024-character limit per file by chunking data.
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

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules(modules)

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {yaml_content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(priv_dir, filename)

      case File.write(file_path, yaml_content) do
        :ok -> Logger.info("Wrote #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_modules(modules) do
    do_chunk(modules, [], [])
  end

  defp do_chunk([], current_chunk, all_chunks) do
    if current_chunk == [] do
      Enum.reverse(all_chunks)
    else
      Enum.reverse([generate_yaml(Enum.reverse(current_chunk)) | all_chunks])
    end
  end

  defp do_chunk([mod | rest], current_chunk, all_chunks) do
    yaml = generate_yaml(Enum.reverse([mod | current_chunk]))

    if String.length(yaml) > 1024 and current_chunk != [] do
      # Push the current chunk (without the new mod) and start a new chunk with the new mod
      finished_yaml = generate_yaml(Enum.reverse(current_chunk))
      do_chunk(rest, [mod], [finished_yaml | all_chunks])
    else
      # Add mod to current chunk
      do_chunk(rest, [mod | current_chunk], all_chunks)
    end
  end

  defp generate_yaml(modules) do
    data = Enum.map(modules, fn mod -> %{"module" => to_string(mod)} end)

    # We build a simple YAML-like string format since we don't have a YAML dependency
    lines = ["---", "skills:"]

    module_lines = Enum.map(data, fn %{"module" => mod} -> "  - module: #{mod}" end)

    Enum.join(lines ++ module_lines, "\n") <> "\n"
  end
end
