defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically updates SKILL.md documentation files within the 1024 character limits
  per file using a valid YAML format.
  """
  use GenServer
  require Logger

  # Update every 60 minutes
  @interval 60 * 60 * 1000

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
    Logger.info("Starting SKILL.md documentation standardization...")

    # Discover modules
    {:ok, modules} = :application.get_key(:governance_core, :modules)

    # Convert to formatted YAML entry string for each module
    entries =
      modules
      |> Enum.map(&format_module_entry/1)
      |> Enum.filter(&(&1 != nil))

    # Chunk by character limits
    chunks = chunk_by_length(entries, 1024)

    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    # Write multiple files to avoid limit
    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)

      content = """
      ---
      # GovernanceCore Auto-Generated SKILL
      version: 1.0
      modules:
      #{chunk}
      ...
      """
      File.write!(filepath, content)
    end)

    Logger.info("SKILL.md documentation updated.")
  end

  defp format_module_entry(mod) do
    name = inspect(mod)
    # Simple formatting for documentation
    "  - name: #{name}\n"
  end

  defp chunk_by_length(entries, max_length) do
    Enum.reduce(entries, {[], ""}, fn entry, {chunks, current_chunk} ->
      # Estimate overhead length (YAML frontmatter + end)
      overhead = 100

      if String.length(current_chunk) + String.length(entry) + overhead > max_length do
        # Start a new chunk
        {[current_chunk | chunks], entry}
      else
        {chunks, current_chunk <> entry}
      end
    end)
    |> then(fn {chunks, current_chunk} ->
      if current_chunk != "" do
        [current_chunk | chunks]
      else
        chunks
      end
    end)
    |> Enum.reverse()
  end
end
