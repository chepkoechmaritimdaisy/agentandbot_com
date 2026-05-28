defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  A GenServer that tracks module changes and updates SKILL.md.
  Enforces a strict 1024 character limit per file using YAML format.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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
    perform_track()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  def perform_track do
    Logger.info("Starting SkillTracker update...")

    case :application.get_key(:governance_core, :modules) do
      {:ok, modules} ->
        chunked_skills = chunk_modules(modules)
        write_skills(chunked_skills)
      _ ->
        Logger.error("SkillTracker: Failed to get modules from application.")
    end
  end

  defp chunk_modules(modules) do
    # Chunk the modules into lists of modules such that the YAML representation
    # of each chunk is under 1024 characters.
    Enum.reduce(modules, [[]], fn module, acc ->
      current_chunk = hd(acc)
      new_chunk = current_chunk ++ [module]
      yaml = generate_yaml(new_chunk)

      if String.length(yaml) > 1024 do
        # If adding the module exceeds 1024, start a new chunk
        [[module] | acc]
      else
        [new_chunk | tl(acc)]
      end
    end)
    |> Enum.reverse()
  end

  defp generate_yaml(modules) do
    "skills:\n" <> Enum.map_join(modules, "\n", fn mod -> "  - #{inspect(mod)}" end)
  end

  defp write_skills(chunked_skills) do
    priv_dir = Path.join(File.cwd!(), "priv")

    Enum.with_index(chunked_skills, fn chunk, index ->
      filename = if index == 0, do: "SKILL.md", else: "SKILL_#{index + 1}.md"
      filepath = Path.join(priv_dir, filename)
      yaml_content = generate_yaml(chunk)

      case File.write(filepath, yaml_content) do
        :ok ->
          Logger.info("SkillTracker: Successfully wrote #{filename}.")
        {:error, reason} ->
          Logger.error("SkillTracker: Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end
end
