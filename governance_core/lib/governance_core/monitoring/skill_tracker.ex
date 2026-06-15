defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer to dynamically manage SKILL.md documentation.
  Chunks module documentation into YAML files, enforcing a 1024-character limit per file.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

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
        yaml_chunks = chunk_modules(modules)
        write_chunks(yaml_chunks)
      _ ->
        Logger.error("Failed to retrieve modules for SKILL.md update")
    end
  end

  defp chunk_modules(modules) do
    # Generate simple YAML representation for each module
    module_yamls = Enum.map(modules, fn mod -> "- module: #{inspect(mod)}\n" end)

    Enum.reduce(module_yamls, {[], ""}, fn yaml_str, {chunks, current_chunk} ->
      new_chunk = current_chunk <> yaml_str
      if String.length(new_chunk) > 1024 do
        # Push current chunk and start a new one
        {[current_chunk | chunks], yaml_str}
      else
        {chunks, new_chunk}
      end
    end)
    |> then(fn {chunks, last_chunk} ->
      [last_chunk | chunks]
      |> Enum.reject(&(&1 == ""))
      |> Enum.reverse()
    end)
  end

  defp write_chunks(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk_content, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      file_path = Path.join(priv_dir, filename)

      # Ensure YAML formatting block
      full_content = "---\n#{chunk_content}---"

      case File.write(file_path, full_content) do
        :ok -> Logger.info("Updated #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
