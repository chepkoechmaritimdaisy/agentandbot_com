defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically discovers application modules and documents them dynamically into YAML chunks (SKILL.md) ensuring the max characters are respected.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_track()
    {:ok, state}
  end

  @impl true
  def handle_info(:track, state) do
    track_skills()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  defp track_skills do
    Logger.info("SkillTracker: Generating SKILL.md...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        # We need to chunk the modules list (20 per file) to enforce the 1024 char limit
        chunks = Enum.chunk_every(modules, 20)

        priv_dir = Path.join(File.cwd!(), "priv")
        File.mkdir_p!(priv_dir)

        Enum.with_index(chunks, 1)
        |> Enum.each(fn {chunk, index} ->
          filename = if index == 1, do: "SKILL.md", else: "SKILL_#{index}.md"
          filepath = Path.join(priv_dir, filename)

          # Format correctly with YAML multiline scalars indented
          yaml_content = "modules: |\n" <> Enum.map_join(chunk, "\n", fn mod -> "  #{inspect(mod)}" end)

          case File.write(filepath, yaml_content) do
            :ok -> Logger.debug("SkillTracker: Wrote #{filename}")
            {:error, reason} -> Logger.error("SkillTracker: Failed to write #{filename}: #{inspect(reason)}")
          end
        end)

      _ ->
        Logger.error("SkillTracker: Could not retrieve modules.")
    end
  end
end
