defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer that continuously generates standardized SKILL.md documentation
  for all discovered modules in the application.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000

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
    update_skill_docs()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp update_skill_docs do
    Logger.info("Updating SKILL.md files...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Basic parsing to extract some dummy info per module.
        # In a real scenario we might use Code.fetch_docs/1
        module_info = Enum.map(modules, fn mod ->
          %{
            "module" => inspect(mod),
            "description" => "Auto-generated documentation for #{inspect(mod)}"
          }
        end)

        chunked_write(module_info)

      :undefined ->
        Logger.error("Failed to load application modules for SKILL.md generation")
    end
  end

  defp chunked_write(all_info) do
    # Chunk logic to keep each YAML file under 1024 characters
    # Calculate length dynamically to ensure safety
    chunks = chunk_by_size(all_info, 1024, [], [])

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      yaml_content = generate_yaml(chunk)

      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(File.cwd!(), "priv/#{filename}")

      case File.write(file_path, yaml_content) do
        :ok ->
          Logger.info("Successfully wrote #{filename}")
        {:error, reason} ->
          Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  # Helper to recursively chunk items so that the resulting YAML string
  # for the chunk does not exceed max_size.
  defp chunk_by_size([], _max_size, current_chunk, acc) do
    Enum.reverse([Enum.reverse(current_chunk) | acc])
  end

  defp chunk_by_size([item | rest], max_size, current_chunk, acc) do
    test_chunk = [item | current_chunk]
    test_yaml = generate_yaml(Enum.reverse(test_chunk))

    if String.length(test_yaml) > max_size and not Enum.empty?(current_chunk) do
      # Item doesn't fit, push current_chunk to acc and start new chunk
      chunk_by_size(rest, max_size, [item], [Enum.reverse(current_chunk) | acc])
    else
      # Item fits (or it's the first item and we must include it anyway)
      chunk_by_size(rest, max_size, test_chunk, acc)
    end
  end

  defp generate_yaml(items) do
    # Extremely basic pseudo-YAML generation for the map
    # A real YAML library would be better, but we are avoiding extra deps if possible
    lines = Enum.flat_map(items, fn %{"module" => m, "description" => d} ->
      [
        "- module: \"#{m}\"",
        "  description: \"#{d}\""
      ]
    end)

    Enum.join(lines, "\n") <> "\n"
  end
end
