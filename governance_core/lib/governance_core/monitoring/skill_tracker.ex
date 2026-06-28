defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically discovers loaded modules and generates standard YAML SKILL.md docs.
  Chunks data to enforce a strict 1024-character limit per generated file.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour
  @max_chars 1024

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
    generate_skills()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  defp generate_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        yaml_blocks = Enum.map(modules, &format_module/1)
        chunked_writes(yaml_blocks, 1, "", [])
        Logger.info("SkillTracker: SKILL.md updated.")
      _ ->
        Logger.error("SkillTracker: Failed to get modules.")
    end
  end

  defp format_module(module) do
    """
    - module: #{inspect(module)}
      description: "Auto-discovered module"
    """
  end

  defp chunked_writes([], _index, "", _files_written) do
    :ok
  end

  defp chunked_writes([], index, current_chunk, files_written) do
    write_chunk(index, current_chunk)
    :ok
  end

  defp chunked_writes([block | rest], index, current_chunk, files_written) do
    projected = current_chunk <> block
    if String.length(projected) > @max_chars do
      write_chunk(index, current_chunk)
      chunked_writes(rest, index + 1, block, [index | files_written])
    else
      chunked_writes(rest, index, projected, files_written)
    end
  end

  defp write_chunk(index, content) do
    filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
    path = Path.join(File.cwd!(), "priv/#{filename}")
    # Ensure priv directory exists
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end
end
