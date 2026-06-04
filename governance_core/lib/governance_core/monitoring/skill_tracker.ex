defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically discovers all application modules and writes their documentation
  to SKILL.md files. Chunked to respect a 1024 character file limit.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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

  def update_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        yaml_blocks = Enum.map(modules, fn mod ->
          "- module: #{inspect(mod)}\n"
        end)

        write_chunked_skills(yaml_blocks, 1, [], 0)
      _ ->
        Logger.warning("Could not retrieve application modules for SkillTracker.")
    end
  end

  defp write_chunked_skills([], _index, [], _current_length), do: :ok
  defp write_chunked_skills([], index, current_chunk, _current_length) do
    write_to_file(Enum.reverse(current_chunk), index)
  end
  defp write_chunked_skills([block | rest], index, current_chunk, current_length) do
    block_len = String.length(block)

    # 1024 is the max limit
    if current_length + block_len > 1024 and current_length > 0 do
      # Flush current chunk and start a new one
      write_to_file(Enum.reverse(current_chunk), index)
      write_chunked_skills(rest, index + 1, [block], block_len)
    else
      write_chunked_skills(rest, index, [block | current_chunk], current_length + block_len)
    end
  end

  defp write_to_file(chunk_lines, index) do
    filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
    # Write to source priv folder to ensure it is version controlled
    file_path = Path.join([File.cwd!(), "priv", filename])

    content = "---\nmodules:\n" <> Enum.join(chunk_lines, "")

    case File.write(file_path, content) do
      :ok -> Logger.info("Successfully updated #{filename}")
      {:error, reason} -> Logger.error("Failed to write to #{filename}: #{inspect(reason)}")
    end
  end
end
