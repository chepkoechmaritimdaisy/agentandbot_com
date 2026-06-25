defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks newly added or updated Elixir modules and generates
  standardized YAML SKILL.md documentation files, ensuring a strict 1024 char limit per file.
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
    perform_update()
    schedule_update()
    {:noreply, state}
  end

  defp schedule_update do
    Process.send_after(self(), :update, @interval)
  end

  def perform_update do
    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        Logger.info("SkillTracker: Found #{length(modules)} modules. Generating docs...")
        generate_skill_docs(modules)
      :undefined ->
        Logger.error("SkillTracker: Could not discover application modules.")
    end
  end

  defp generate_skill_docs(modules) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    # Convert modules to YAML representations
    yaml_entries = Enum.map(modules, fn mod ->
      """
      - module: #{inspect(mod)}
        tool: auto_discovered
      """
    end)

    chunk_and_write(yaml_entries, priv_dir, 1, [], 0)
  end

  defp chunk_and_write([], priv_dir, file_index, current_chunk, _current_len) do
    write_chunk(priv_dir, file_index, current_chunk)
  end

  defp chunk_and_write([entry | rest], priv_dir, file_index, current_chunk, current_len) do
    entry_len = String.length(entry)

    if current_len + entry_len > 1024 do
      # Write current chunk and start a new one
      write_chunk(priv_dir, file_index, current_chunk)
      chunk_and_write(rest, priv_dir, file_index + 1, [entry], entry_len)
    else
      chunk_and_write(rest, priv_dir, file_index, current_chunk ++ [entry], current_len + entry_len)
    end
  end

  defp write_chunk(_priv_dir, _file_index, []) do
    :ok
  end

  defp write_chunk(priv_dir, file_index, chunk) do
    filename = if file_index == 1, do: "SKILL.md", else: "SKILL_#{file_index}.md"
    path = Path.join(priv_dir, filename)

    content = Enum.join(chunk, "")
    File.write!(path, content)
    Logger.info("SkillTracker: Wrote #{filename} (#{String.length(content)} chars).")
  end
end
