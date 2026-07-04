defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that dynamically manages tool documentation (`SKILL.md`) by discovering
  modules, chunking them to enforce a 1024-character limit per file, and writing
  the generated YAML files to the `priv` directory.
  """
  use GenServer
  require Logger

  # Update interval (e.g. 1 hour)
  @update_interval 60 * 60 * 1000

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
    Process.send_after(self(), :update, @update_interval)
  end

  def update_skills do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # Filter for tools/features (for simplicity, we grab all modules for now)
        # and create a list of strings representing the YAML blocks for each module.
        yaml_blocks = Enum.map(modules, &format_module_as_yaml/1)
        write_yaml_chunks(yaml_blocks)

      :undefined ->
        Logger.error("Failed to retrieve modules for SKILL.md generation")
    end
  end

  defp format_module_as_yaml(module) do
    # Simple YAML representation
    """
    - module: #{inspect(module)}
      description: "Auto-discovered module"
    """
  end

  defp write_yaml_chunks(yaml_blocks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    chunk_and_write(yaml_blocks, priv_dir, 1, "", 0)
  end

  defp chunk_and_write([], priv_dir, file_index, current_content, _current_length) do
    if current_content != "" do
      write_file(priv_dir, file_index, current_content)
    end
  end

  defp chunk_and_write([block | rest], priv_dir, file_index, current_content, current_length) do
    block_length = String.length(block)

    if current_length + block_length > 1024 do
      # Write current chunk and start a new one
      write_file(priv_dir, file_index, current_content)
      chunk_and_write(rest, priv_dir, file_index + 1, block, block_length)
    else
      chunk_and_write(rest, priv_dir, file_index, current_content <> block, current_length + block_length)
    end
  end

  defp write_file(priv_dir, 1, content) do
    path = Path.join(priv_dir, "SKILL.md")
    File.write!(path, content)
  end

  defp write_file(priv_dir, index, content) do
    path = Path.join(priv_dir, "SKILL_#{index}.md")
    File.write!(path, content)
  end
end
