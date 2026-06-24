defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Dynamically manages SKILL.md tool documentation by tracking application modules,
  chunking data to enforce a strict 1024-character limit per YAML file, and writing
  them to the source priv directory.
  """

  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # Run every 1 hour
  @max_chars 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_track()
    {:ok, state}
  end

  def handle_info(:track, state) do
    track_skills()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  defp track_skills do
    Logger.info("SkillTracker: Generating SKILL.md documentation...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    # Convert modules to simple maps/structs for YAML
    module_docs = Enum.map(modules, fn mod ->
      %{
        module: inspect(mod),
        description: "Auto-generated placeholder for #{inspect(mod)}"
      }
    end)

    # Chunk into multiple files to enforce max character limit on actual YAML length
    chunked_docs = chunk_by_yaml_length(module_docs, @max_chars, [], [])

    Enum.with_index(chunked_docs)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      filepath = Path.join(priv_dir, filename)

      # Since we don't have a full YAML library in deps, we will use JSON or a simple YAML format
      # We'll use a simple manual YAML encoder for this specific format
      yaml_content = encode_yaml(chunk)
      File.write!(filepath, yaml_content)
      Logger.info("SkillTracker: Wrote #{filename} (#{byte_size(yaml_content)} chars)")
    end)
  end

  defp chunk_by_yaml_length([], _max_chars, current_chunk, all_chunks) do
    if current_chunk == [] do
      Enum.reverse(all_chunks)
    else
      Enum.reverse([Enum.reverse(current_chunk) | all_chunks])
    end
  end

  defp chunk_by_yaml_length([doc | rest], max_chars, current_chunk, all_chunks) do
    test_chunk = [doc | current_chunk] |> Enum.reverse()
    yaml_len = byte_size(encode_yaml(test_chunk))

    if yaml_len > max_chars do
      if current_chunk == [] do
        # This single doc is too large, we have to put it in its own chunk anyway
        chunk_by_yaml_length(rest, max_chars, [], [[doc] | all_chunks])
      else
        # Finalize the current chunk and start a new one with this doc
        chunk_by_yaml_length(rest, max_chars, [doc], [Enum.reverse(current_chunk) | all_chunks])
      end
    else
      chunk_by_yaml_length(rest, max_chars, [doc | current_chunk], all_chunks)
    end
  end

  defp encode_yaml(docs) do
    yaml_header = "---\nskills:\n"
    yaml_body = Enum.map_join(docs, "\n", fn doc ->
      "  - module: #{doc.module}\n    description: #{doc.description}"
    end)
    yaml_header <> yaml_body <> "\n---\n"
  end
end
