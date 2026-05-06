defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer that dynamically manages tool documentation (SKILL.md) by
  discovering modules, chunking them to enforce a 1024-character limit
  per file, and writing generated YAML to the project's priv directory.
  """

  use GenServer
  require Logger

  @interval 1_000 * 60 * 60 # 1 hour
  @max_chars 1024

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_update()
    {:ok, %{}}
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
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.filter(&is_governance_module?/1)
        |> generate_yaml_chunks()
        |> write_chunks()
      :undefined ->
        Logger.error("Failed to discover modules for GovernanceCore")
    end
  end

  defp is_governance_module?(module) do
    module
    |> Atom.to_string()
    |> String.starts_with?("Elixir.GovernanceCore.")
  end

  defp generate_yaml_chunks(modules) do
    initial_acc = %{current_chunk: [], chunks: [], current_len: 0}

    result = Enum.reduce(modules, initial_acc, fn module, acc ->
      mod_string = Atom.to_string(module)
      # Create YAML entry and explicitly indent multiline strings for valid YAML structure
      yaml_entry = """
      - module: #{mod_string}
        description: |
          Documentation for #{mod_string}
      """
      entry_len = String.length(yaml_entry)

      if acc.current_len + entry_len > @max_chars and acc.current_len > 0 do
        # Start a new chunk
        %{
          current_chunk: [yaml_entry],
          chunks: [acc.current_chunk | acc.chunks],
          current_len: entry_len
        }
      else
        # Add to current chunk
        %{
          acc |
          current_chunk: [yaml_entry | acc.current_chunk],
          current_len: acc.current_len + entry_len
        }
      end
    end)

    # Collect the last chunk
    final_chunks = [result.current_chunk | result.chunks]

    final_chunks
    |> Enum.reject(&Enum.empty?/1)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
  end

  defp write_chunks(chunks) do
    base_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(base_dir)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(base_dir, filename)
      content = Enum.join(chunk, "")

      case File.write(file_path, content) do
        :ok ->
          Logger.info("SkillTracker successfully updated #{filename}")
        {:error, reason} ->
          Logger.error("SkillTracker failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
