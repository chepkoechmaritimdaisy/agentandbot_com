defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  SkillTracker GenServer for SKILL.md Standardization and Updating.
  Periodically discovers application modules and generates standard YAML documentation
  in chunked SKILL.md files to respect the 1024 character limit.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes
  @char_limit 1024

  def start_link(opts \\ []) do
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
    Logger.info("[SkillTracker] Updating SKILL.md documentation...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules_for_yaml(modules)

    write_chunks(chunks)
  end

  defp chunk_modules_for_yaml(modules) do
    # Group modules into chunks such that the generated YAML per chunk is <= 1024 characters
    Enum.reduce(modules, {[], []}, fn mod, {current_chunk, chunks} ->
      mod_str = inspect(mod)

      # Multiline strings in YAML block scalars must be properly indented
      yaml_entry = "  - module: |\n      #{mod_str}\n"

      current_len = calculate_yaml_len(current_chunk)
      entry_len = String.length(yaml_entry)

      if current_len + entry_len > @char_limit and current_chunk != [] do
        # Start a new chunk
        {[yaml_entry], [Enum.reverse(current_chunk) | chunks]}
      else
        # Add to current chunk
        {[yaml_entry | current_chunk], chunks}
      end
    end)
    |> case do
      {[], chunks} -> Enum.reverse(chunks)
      {current_chunk, chunks} -> Enum.reverse([Enum.reverse(current_chunk) | chunks])
    end
  end

  defp calculate_yaml_len(chunk_entries) do
    base_len = String.length("skills:\n")
    entries_len = Enum.map(chunk_entries, &String.length/1) |> Enum.sum()
    base_len + entries_len
  end

  defp write_chunks(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)

    chunks
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
      filepath = Path.join(priv_dir, filename)

      yaml_content = "skills:\n" <> Enum.join(chunk)

      case File.write(filepath, yaml_content) do
        :ok ->
          Logger.info("[SkillTracker] Successfully wrote #{filename}")
        {:error, posix} ->
          Logger.error("[SkillTracker] Failed to write #{filename}: #{inspect(posix)}")
      end
    end)
  end
end