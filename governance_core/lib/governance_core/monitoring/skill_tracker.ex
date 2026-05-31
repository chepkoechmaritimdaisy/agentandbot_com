defmodule GovernanceCore.Monitoring.SkillTracker do
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # Run every hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def handle_info(:update_skills, state) do
    update_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update_skills, @interval)
  end

  defp update_skills do
    Logger.info("Updating SKILL.md...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        yaml_chunks = create_yaml_chunks(modules)
        write_chunks_to_files(yaml_chunks)
      _ ->
        Logger.error("Failed to retrieve modules for SKILL.md generation.")
    end
  end

  defp create_yaml_chunks(modules) do
    yaml_header = "modules:\n"

    {chunks, current_chunk, _current_len} =
      Enum.reduce(modules, {[], yaml_header, String.length(yaml_header)}, fn mod, {chunks_acc, current_chunk_acc, current_len_acc} ->
        mod_str = "  - #{inspect(mod)}\n"
        mod_len = String.length(mod_str)

        if current_len_acc + mod_len > 1024 do
          {chunks_acc ++ [current_chunk_acc], yaml_header <> mod_str, String.length(yaml_header) + mod_len}
        else
          {chunks_acc, current_chunk_acc <> mod_str, current_len_acc + mod_len}
        end
      end)

    chunks ++ [current_chunk]
  end

  defp write_chunks_to_files(chunks) do
    Enum.with_index(chunks, fn chunk, index ->
      filename =
        if index == 0 do
          "SKILL.md"
        else
          "SKILL_#{index + 1}.md"
        end

      path = Path.join(File.cwd!(), "priv/#{filename}")

      case File.write(path, chunk) do
        :ok -> Logger.info("Successfully written #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
