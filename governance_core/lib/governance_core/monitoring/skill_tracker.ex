defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Automatically tracks and updates SKILL.md for tools and endpoints.
  Generates documentation adhering to universal standards (YAML format, max 1024 chars).
  """
  use GenServer
  require Logger

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
    perform_track()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  def perform_track do
    Logger.info("Starting Skill Tracker...")

    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    chunks = chunk_modules(modules)

    priv_dir = Path.join(File.cwd!(), "priv")

    Enum.with_index(chunks, fn {chunk, idx} ->
      filename = if idx == 0, do: "SKILL.md", else: "SKILL_#{idx + 1}.md"
      filepath = Path.join(priv_dir, filename)

      yaml_content = generate_yaml(chunk)

      case File.write(filepath, yaml_content) do
        :ok -> Logger.info("Generated #{filename}")
        {:error, reason} -> Logger.error("Failed to write #{filename}: #{inspect(reason)}")
      end
    end)
  end

  defp chunk_modules(modules) do
    do_chunk(modules, [], [])
  end

  defp do_chunk([], current_chunk, acc) do
    if current_chunk == [], do: Enum.reverse(acc), else: Enum.reverse([Enum.reverse(current_chunk) | acc])
  end

  defp do_chunk([mod | rest], current_chunk, acc) do
    test_chunk = [mod | current_chunk]
    test_yaml = generate_yaml(test_chunk)

    if String.length(test_yaml) > 1024 do
      # Test chunk is too big, start a new chunk with current mod
      # If current_chunk is empty, mod itself is > 1024 (edge case), just put it in a chunk anyway.
      if current_chunk == [] do
        do_chunk(rest, [], [[mod] | acc])
      else
        do_chunk(rest, [mod], [Enum.reverse(current_chunk) | acc])
      end
    else
      do_chunk(rest, test_chunk, acc)
    end
  end

  defp generate_yaml(modules) do
    """
    tools:
    #{Enum.map_join(modules, "\n", &"  - name: #{inspect(&1)}")}\n
    """
  end
end
