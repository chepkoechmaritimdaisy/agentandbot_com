defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that discovers modules and generates standard SKILL.md documentation
  chunked by 1024-character limits to avoid truncation.
  """
  use GenServer
  require Logger

  # Nightly run is 24 hours, but we will use the continuous interval here for discovery logic
  # if needed, or 24h. Project specs say "arka planda... otomatik oluşturur", we'll run it every 5 minutes.
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_tracking()
    {:ok, state}
  end

  def handle_info(:track, state) do
    perform_tracking()
    schedule_tracking()
    {:noreply, state}
  end

  defp schedule_tracking do
    Process.send_after(self(), :track, @interval)
  end

  defp perform_tracking do
    Logger.info("Starting Skill Tracker update...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules(modules)

    write_chunks(chunks)

    Logger.info("Skill Tracker update completed.")
  end

  defp chunk_modules(modules) do
    Enum.reduce(modules, {[], []}, fn mod, {current_chunk, chunks} ->
      mod_string = "  - #{inspect(mod)}\n"
      yaml_part = build_yaml(current_chunk ++ [mod_string])

      if String.length(yaml_part) > 1024 do
        {[mod_string], chunks ++ [current_chunk]}
      else
        {current_chunk ++ [mod_string], chunks}
      end
    end)
    |> fn {last_chunk, chunks} ->
      if Enum.empty?(last_chunk) do
        chunks
      else
        chunks ++ [last_chunk]
      end
    end.()
  end

  defp build_yaml(mod_strings) do
    """
    tools:
    #{Enum.join(mod_strings)}
    """
  end

  defp write_chunks(chunks) do
    base_dir = Path.join(File.cwd!(), "priv")

    # Ensure priv directory exists
    File.mkdir_p!(base_dir)

    Enum.with_index(chunks, 1)
    |> Enum.each(fn {chunk, index} ->
      filename =
        if index == 1 do
          "SKILL.md"
        else
          "SKILL_#{index}.md"
        end

      filepath = Path.join(base_dir, filename)
      content = build_yaml(chunk)

      case File.write(filepath, content) do
        :ok -> :ok
        {:error, reason} ->
          Logger.error("Failed to write #{filepath}: #{inspect(reason)}")
      end
    end)
  end
end
