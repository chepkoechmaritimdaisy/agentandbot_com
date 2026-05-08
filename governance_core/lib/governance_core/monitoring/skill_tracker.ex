defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  GenServer to dynamically manage SKILL.md documentation.
  Runs periodically to ensure documented modules match currently loaded modules.
  Enforces a 1024-character limit per file by chunking.
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
    Logger.info("Starting SKILL.md generation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # We'll document each module with its string name.
        module_names = Enum.map(modules, &inspect/1)

        # Enforce 1024-char limit by dynamically building YAML strings
        chunks = chunk_modules(module_names, [], [], 0)

        write_chunks(chunks)

      :undefined ->
        Logger.error("Failed to retrieve modules for governance_core")
    end
  end

  defp chunk_modules([], current_chunk, all_chunks, _current_size) do
    Enum.reverse([Enum.reverse(current_chunk) | all_chunks])
  end

  defp chunk_modules([mod | rest], current_chunk, all_chunks, current_size) do
    # Approximate YAML size for this module entry
    mod_yaml = "- #{mod}\n"
    mod_size = byte_size(mod_yaml)

    # +20 for "modules:\n" header space
    if current_size + mod_size > 1000 and current_chunk != [] do
      chunk_modules([mod | rest], [], [Enum.reverse(current_chunk) | all_chunks], 0)
    else
      chunk_modules(rest, [mod_yaml | current_chunk], all_chunks, current_size + mod_size)
    end
  end

  defp write_chunks(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    Enum.with_index(chunks, fn chunk_lines, index ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      filepath = Path.join(priv_dir, filename)

      content = "modules:\n" <> Enum.join(chunk_lines)

      case File.write(filepath, content) do
        :ok -> Logger.info("Successfully wrote #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
