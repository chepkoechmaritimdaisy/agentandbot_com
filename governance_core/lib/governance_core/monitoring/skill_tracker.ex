defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that dynamically manages and standardizes tool documentation (SKILL.md)
  for modules within the application.
  """

  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @max_chars 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_track()
    {:ok, state}
  end

  def handle_info(:track, state) do
    perform_track()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  defp perform_track do
    Logger.info("Starting Skill Tracker Documentation Generation...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        yaml_chunks = chunk_modules_to_yaml(modules)
        write_chunks_to_files(yaml_chunks)
      :undefined ->
        Logger.error("Failed to retrieve modules for governance_core application")
    end
  end

  defp chunk_modules_to_yaml(modules) do
    # Group modules into chunks where the YAML representation is strictly <= 1024 chars
    Enum.reduce(modules, [{[], 0}], fn mod, acc ->
      [{current_chunk, current_len} | rest_chunks] = acc

      mod_string = Atom.to_string(mod)
      # Minimal YAML entry length
      entry_len = String.length("- module: #{mod_string}\n")

      if current_len + entry_len > @max_chars do
        # Start a new chunk
        [{[mod], entry_len}, {current_chunk, current_len} | rest_chunks]
      else
        # Add to current chunk
        [{[mod | current_chunk], current_len + entry_len} | rest_chunks]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {chunk, _len} ->
      chunk
      |> Enum.reverse()
      |> Enum.map(fn m -> "- module: #{m}\n" end)
      |> Enum.join("")
    end)
  end

  defp write_chunks_to_files(chunks) do
    priv_dir = Path.join(File.cwd!(), "priv")

    case File.mkdir_p(priv_dir) do
      :ok ->
        chunks
        |> Enum.with_index(1)
        |> Enum.each(fn {yaml_data, index} ->
          filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
          filepath = Path.join(priv_dir, filename)

          # Use File.write/2 with case to prevent GenServer crash
          case File.write(filepath, yaml_data) do
            :ok -> Logger.debug("Successfully wrote #{filename}")
            {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
          end
        end)
      {:error, reason} ->
        Logger.error("Failed to create priv directory: #{inspect(reason)}")
    end
  end
end
